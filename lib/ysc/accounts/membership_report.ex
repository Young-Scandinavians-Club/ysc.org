defmodule Ysc.Accounts.MembershipReport do
  @moduledoc """
  Queries for generating membership activity reports over a date range.

  Each member appears in only one display list at the highest state they've
  reached: purchased/returning > accepted > rejected > pending.

  Accepted/rejected/pending are derived from `User.state` (the field the rest
  of the app treats as authoritative for access) as of `date_to`, using the
  `Ysc.Accounts.UserEvent` audit trail to know when a state transition
  happened. This keeps the report correct regardless of which admin flow
  changed the user's status (the application-review Approve/Deny buttons, or
  a direct account-status edit), and keeps a report for a past window stable
  even if the user's status changes again after that window closes. Older
  rows that predate the audit trail fall back to the SignupApplication's own
  `review_outcome`/`reviewed_at`.

  Purchased vs. returning: a subscription starting in the window is dropped
  entirely if the member already had coverage at `date_to`'s window start
  (so ordinary renewals and mid-window blips for existing members aren't
  reported); otherwise it's "returning" if the member has an earlier
  subscription on record, or "purchased" if this is their first ever.

  Raw `counts` are unfiltered (for the stats summary at the top of the report).

  Only primary account holders (`primary_user_id == nil`) are ever queried;
  family sub-accounts never appear as their own row, even if they have their
  own SignupApplication or Subscription on record.

  Purchased/returning/expired subscriptions only count for users who have a
  SignupApplication on file, so board-created or otherwise application-less
  accounts (e.g. admins with a manually-attached subscription) don't appear
  as memberships "purchased" through the normal intake pipeline.
  """

  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Accounts.{User, SignupApplication, UserEvent}
  alias Ysc.Subscriptions.Subscription

  @report_timezone "America/Los_Angeles"

  @spec generate(Date.t(), Date.t()) :: map()
  def generate(date_from, date_to) do
    start_dt = DateTime.new!(date_from, ~T[00:00:00], @report_timezone)
    end_dt = DateTime.new!(date_to, ~T[23:59:59], @report_timezone)

    %{
      submitted: all_submitted,
      expired: expired,
      purchases: %{purchased: purchased, returning: returning}
    } = fetch_report_sources(start_dt, end_dt)

    %{pending: pending_raw, accepted: accepted, rejected: rejected} =
      classify_applications(all_submitted, start_dt, end_dt)

    # Raw counts for the stats summary (unfiltered)
    counts = %{
      applied: length(all_submitted),
      accepted: length(accepted),
      rejected: length(rejected),
      pending: length(pending_raw),
      expired: length(expired),
      purchased: length(purchased),
      returning: length(returning)
    }

    # Deduplicate display lists: each user appears only in their highest category.
    # Priority: purchased/returning > accepted > rejected > pending
    subscription_ids = MapSet.new(purchased ++ returning, & &1.user_id)

    accepted_display =
      Enum.reject(accepted, &MapSet.member?(subscription_ids, &1.user_id))

    excluded_from_pending =
      subscription_ids
      |> MapSet.union(MapSet.new(accepted_display, & &1.user_id))
      |> MapSet.union(MapSet.new(rejected, & &1.user_id))

    pending_display =
      Enum.reject(
        pending_raw,
        &MapSet.member?(excluded_from_pending, &1.user_id)
      )

    purchased_ids = MapSet.new(purchased, & &1.id)

    subscriptions_with_apps =
      attach_applications(purchased ++ returning)

    {purchased_with_apps, returning_with_apps} =
      Enum.split_with(
        subscriptions_with_apps,
        &MapSet.member?(purchased_ids, &1.id)
      )

    %{
      date_from: date_from,
      date_to: date_to,
      pending: pending_display,
      accepted: accepted_display,
      rejected: rejected,
      expired: expired,
      purchased: purchased_with_apps,
      returning: returning_with_apps,
      counts: counts
    }
  end

  # list_submitted, list_expired, and list_purchases are independent; run them
  # concurrently to cut report wall time on wide date ranges.
  defp fetch_report_sources(start_dt, end_dt) do
    parent = self()

    [
      {:submitted, fn -> list_submitted(start_dt, end_dt) end},
      {:expired, fn -> list_expired(start_dt, end_dt) end},
      {:purchases, fn -> list_purchases(start_dt, end_dt) end}
    ]
    |> Task.async_stream(
      fn {key, fun} ->
        allow_async_repo_access(parent)
        {key, fun.()}
      end,
      timeout: :infinity,
      max_concurrency: 3
    )
    |> Enum.reduce(%{}, fn {:ok, {key, value}}, acc ->
      Map.put(acc, key, value)
    end)
  end

  defp allow_async_repo_access(owner_pid) do
    if Application.get_env(:ysc, :sql_sandbox) do
      try do
        Ecto.Adapters.SQL.Sandbox.allow(Ysc.Repo, self(), owner_pid)
      rescue
        _ -> :ok
      end
    end
  end

  @spec to_csv(map()) :: String.t()
  def to_csv(report) do
    header = [
      "Category",
      "Name",
      "Email",
      "Date",
      "Membership Type",
      "Status",
      "Eligibility",
      "Link to Scandinavia",
      "How They Heard",
      "Occupation",
      "City",
      "Country"
    ]

    rows =
      application_rows("Pending", report.pending) ++
        application_rows("Accepted", report.accepted) ++
        application_rows("Rejected", report.rejected) ++
        subscription_rows("Purchased", report.purchased, :start_date) ++
        subscription_rows("Returning", report.returning, :start_date) ++
        subscription_rows("Expired", report.expired, :current_period_end)

    [header | rows]
    |> CSV.encode()
    |> Enum.join()
  end

  # --- Application classification (pending / accepted / rejected) ---

  defp list_submitted(start_dt, end_dt) do
    from(sa in SignupApplication,
      join: u in User,
      on: u.id == sa.user_id,
      where: is_nil(u.primary_user_id),
      where: not is_nil(sa.completed),
      where: sa.completed >= ^start_dt and sa.completed <= ^end_dt,
      preload: [user: u],
      order_by: [asc: sa.completed]
    )
    |> Repo.all()
  end

  # For each submitted application, classifies the user as pending, accepted,
  # or rejected based on their current User.state and the UserEvent audit
  # trail as of end_dt (falling back to the application's own review fields
  # for rows that predate the audit trail).
  defp classify_applications(all_submitted, start_dt, end_dt) do
    user_ids = all_submitted |> Enum.map(& &1.user_id) |> Enum.uniq()
    events_by_user = latest_state_events_by_user(user_ids, end_dt)

    all_submitted
    |> Enum.reduce(%{pending: [], accepted: [], rejected: []}, fn app, acc ->
      case classify_application(
             app,
             Map.get(events_by_user, app.user_id),
             start_dt,
             end_dt
           ) do
        {:pending, app} -> %{acc | pending: [app | acc.pending]}
        {:accepted, app} -> %{acc | accepted: [app | acc.accepted]}
        {:rejected, app} -> %{acc | rejected: [app | acc.rejected]}
        :other -> acc
      end
    end)
    |> Map.new(fn {key, apps} -> {key, Enum.reverse(apps)} end)
  end

  defp latest_state_events_by_user(user_ids, end_dt) do
    from(e in UserEvent,
      where: e.type == ^"state_update",
      where: e.user_id in ^user_ids,
      where: e.inserted_at <= ^end_dt,
      distinct: e.user_id,
      order_by: [asc: e.user_id, desc: e.inserted_at],
      select: %{user_id: e.user_id, to: e.to, inserted_at: e.inserted_at}
    )
    |> Repo.all()
    |> Map.new(&{&1.user_id, &1})
  end

  # No UserEvent audit trail for this user (e.g. their state changed before
  # the audit trail existed). Falls back to the SignupApplication's own
  # review fields when present; otherwise trusts the user's current
  # `state` directly rather than defaulting a since-accepted/rejected
  # member to "pending" just because `review_outcome` was never backfilled.
  defp classify_application(app, nil, start_dt, end_dt) do
    cond do
      app.review_outcome == :approved and not is_nil(app.reviewed_at) and
          in_range?(app.reviewed_at, start_dt, end_dt) ->
        {:accepted, app}

      app.review_outcome == :rejected and not is_nil(app.reviewed_at) and
          in_range?(app.reviewed_at, start_dt, end_dt) ->
        {:rejected, app}

      is_nil(app.review_outcome) and app.user.state == :active ->
        {:accepted,
         %{app | reviewed_at: app.completed, review_outcome: :approved}}

      is_nil(app.review_outcome) and app.user.state == :rejected ->
        {:rejected,
         %{app | reviewed_at: app.completed, review_outcome: :rejected}}

      is_nil(app.review_outcome) and app.user.state == :pending_approval ->
        {:pending, app}

      true ->
        :other
    end
  end

  defp classify_application(
         app,
         %{to: "active", inserted_at: ts},
         start_dt,
         end_dt
       ) do
    if in_range?(ts, start_dt, end_dt) do
      {:accepted, %{app | reviewed_at: ts, review_outcome: :approved}}
    else
      :other
    end
  end

  defp classify_application(
         app,
         %{to: "rejected", inserted_at: ts},
         start_dt,
         end_dt
       ) do
    if in_range?(ts, start_dt, end_dt) do
      {:rejected, %{app | reviewed_at: ts, review_outcome: :rejected}}
    else
      :other
    end
  end

  defp classify_application(app, %{to: "pending_approval"}, _start_dt, _end_dt) do
    {:pending, app}
  end

  defp classify_application(_app, %{to: _other}, _start_dt, _end_dt), do: :other

  defp in_range?(%DateTime{} = dt, start_dt, end_dt) do
    DateTime.compare(dt, start_dt) != :lt and
      DateTime.compare(dt, end_dt) != :gt
  end

  # --- Expired subscriptions ---

  defp list_expired(start_dt, end_dt) do
    from(s in Subscription,
      join: u in User,
      on: u.id == s.user_id,
      join: sa in SignupApplication,
      on: sa.user_id == u.id,
      where: is_nil(u.primary_user_id),
      where: s.stripe_status in ["canceled", "cancelled", "unpaid"],
      where: not is_nil(s.current_period_end),
      where:
        s.current_period_end >= ^start_dt and s.current_period_end <= ^end_dt,
      preload: [user: u],
      order_by: [asc: s.current_period_end]
    )
    |> Repo.all()
  end

  # --- Purchased / returning subscriptions ---

  # Finds subscriptions that started in the window, then splits them into
  # "purchased" (first membership ever) and "returning" (member had a prior
  # subscription that had already lapsed). Members who already had coverage
  # at the window's start date are dropped entirely, whether they're renewing
  # normally or repurchased after a lapse mid-window.
  #
  # Classification is pushed into SQL so we don't load every historical
  # subscription row for each candidate user.
  defp list_purchases(start_dt, end_dt) do
    covered_at_start =
      from(s2 in Subscription,
        where: s2.user_id == parent_as(:candidate).user_id,
        where: not is_nil(s2.start_date),
        where: s2.start_date <= ^start_dt,
        where:
          is_nil(s2.current_period_end) or s2.current_period_end >= ^start_dt
      )

    prior_subscription =
      from(s2 in Subscription,
        where: s2.user_id == parent_as(:candidate).user_id,
        where: s2.id != parent_as(:candidate).id,
        where: not is_nil(s2.start_date),
        where: s2.start_date < parent_as(:candidate).start_date
      )

    base_candidates =
      from(s in Subscription,
        as: :candidate,
        join: u in User,
        on: u.id == s.user_id,
        join: sa in SignupApplication,
        on: sa.user_id == u.id,
        where: is_nil(u.primary_user_id),
        where: s.stripe_status in ["active", "trialing"],
        where: not is_nil(s.start_date),
        where: s.start_date >= ^start_dt and s.start_date <= ^end_dt,
        where: not exists(subquery(covered_at_start)),
        preload: [user: u],
        order_by: [asc: s.start_date]
      )

    purchased =
      base_candidates
      |> where([s], not exists(subquery(prior_subscription)))
      |> Repo.all()

    returning =
      base_candidates
      |> where([s], exists(subquery(prior_subscription)))
      |> Repo.all()

    %{purchased: purchased, returning: returning}
  end

  # Attaches each user's SignupApplication (if any) to their subscription struct
  # so the report page can show application details for purchased/returning memberships.
  defp attach_applications([]), do: []

  defp attach_applications(subscriptions) do
    user_ids = Enum.map(subscriptions, & &1.user_id)

    app_by_user =
      from(sa in SignupApplication, where: sa.user_id in ^user_ids)
      |> Repo.all()
      |> Map.new(&{&1.user_id, &1})

    Enum.map(subscriptions, fn sub ->
      Map.put(sub, :signup_application, Map.get(app_by_user, sub.user_id))
    end)
  end

  # --- CSV row builders ---

  defp application_rows(category, applications) do
    Enum.map(applications, fn app ->
      [
        category,
        "#{app.user.first_name} #{app.user.last_name}",
        app.user.email,
        format_date(app.completed),
        to_string(app.membership_type || ""),
        format_review_outcome(app.review_outcome),
        format_eligibility(app.membership_eligibility),
        app.link_to_scandinavia || "",
        app.hear_about_the_club || "",
        app.occupation || "",
        app.city || "",
        app.country || ""
      ]
    end)
  end

  defp subscription_rows(category, subscriptions, date_field) do
    Enum.map(subscriptions, fn sub ->
      case Map.get(sub, :signup_application) do
        %SignupApplication{} = app ->
          [
            category,
            "#{sub.user.first_name} #{sub.user.last_name}",
            sub.user.email,
            format_date(Map.get(sub, date_field)),
            to_string(app.membership_type || ""),
            sub.stripe_status,
            format_eligibility(app.membership_eligibility),
            app.link_to_scandinavia || "",
            app.hear_about_the_club || "",
            app.occupation || "",
            app.city || "",
            app.country || ""
          ]

        _ ->
          [
            category,
            "#{sub.user.first_name} #{sub.user.last_name}",
            sub.user.email,
            format_date(Map.get(sub, date_field)),
            "",
            sub.stripe_status,
            "",
            "",
            "",
            "",
            "",
            ""
          ]
      end
    end)
  end

  defp format_date(nil), do: ""

  defp format_date(%DateTime{} = dt),
    do: dt |> DateTime.to_date() |> Date.to_iso8601()

  defp format_date(%Date{} = d), do: Date.to_iso8601(d)

  defp format_review_outcome(nil), do: "Pending"
  defp format_review_outcome(outcome), do: String.capitalize(to_string(outcome))

  defp format_eligibility(nil), do: ""
  defp format_eligibility([]), do: ""

  defp format_eligibility(eligibility) do
    lookup = SignupApplication.eligibility_lookup()

    Enum.map_join(eligibility, "; ", &Map.get(lookup, &1, to_string(&1)))
  end
end
