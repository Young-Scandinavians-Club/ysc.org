defmodule Ysc.Accounts.MembershipReport do
  @moduledoc """
  Queries for generating membership activity reports over a date range.

  Each member appears in only one display list at the highest state they've
  reached: purchased > accepted > rejected > pending.

  Raw `counts` are unfiltered (for the stats summary at the top of the report).
  """

  import Ecto.Query, warn: false

  alias Ysc.Repo
  alias Ysc.Accounts.{User, SignupApplication}
  alias Ysc.Subscriptions.Subscription

  @spec generate(Date.t(), Date.t()) :: map()
  def generate(date_from, date_to) do
    start_dt = DateTime.new!(date_from, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(date_to, ~T[23:59:59], "Etc/UTC")

    all_submitted = list_submitted(start_dt, end_dt)
    accepted = list_accepted(start_dt, end_dt)
    rejected = list_rejected(start_dt, end_dt)
    expired = list_expired(start_dt, end_dt)
    purchased = list_purchased(start_dt, end_dt)

    # Pending = submitted with no review outcome
    pending_raw = Enum.filter(all_submitted, &is_nil(&1.review_outcome))

    # Raw counts for the stats summary (unfiltered)
    counts = %{
      applied: length(all_submitted),
      accepted: length(accepted),
      rejected: length(rejected),
      pending: length(pending_raw),
      expired: length(expired),
      purchased: length(purchased)
    }

    # Deduplicate display lists: each user appears only in their highest category.
    # Priority: purchased > accepted > rejected > pending
    purchased_ids = MapSet.new(purchased, & &1.user_id)

    accepted_display =
      Enum.reject(accepted, &MapSet.member?(purchased_ids, &1.user_id))

    excluded_from_pending =
      purchased_ids
      |> MapSet.union(MapSet.new(accepted_display, & &1.user_id))
      |> MapSet.union(MapSet.new(rejected, & &1.user_id))

    pending_display =
      Enum.reject(
        pending_raw,
        &MapSet.member?(excluded_from_pending, &1.user_id)
      )

    %{
      date_from: date_from,
      date_to: date_to,
      pending: pending_display,
      accepted: accepted_display,
      rejected: rejected,
      expired: expired,
      purchased: attach_applications(purchased),
      counts: counts
    }
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
        subscription_rows("Expired", report.expired, :current_period_end)

    [header | rows]
    |> CSV.encode()
    |> Enum.join()
  end

  # --- Queries ---

  defp list_submitted(start_dt, end_dt) do
    from(sa in SignupApplication,
      join: u in User,
      on: u.id == sa.user_id,
      where: not is_nil(sa.completed),
      where: sa.completed >= ^start_dt and sa.completed <= ^end_dt,
      preload: [user: u],
      order_by: [asc: sa.completed]
    )
    |> Repo.all()
  end

  defp list_accepted(start_dt, end_dt) do
    from(sa in SignupApplication,
      join: u in User,
      on: u.id == sa.user_id,
      where: sa.review_outcome == ^"approved",
      where: not is_nil(sa.reviewed_at),
      where: sa.reviewed_at >= ^start_dt and sa.reviewed_at <= ^end_dt,
      preload: [user: u],
      order_by: [asc: sa.reviewed_at]
    )
    |> Repo.all()
  end

  defp list_rejected(start_dt, end_dt) do
    from(sa in SignupApplication,
      join: u in User,
      on: u.id == sa.user_id,
      where: sa.review_outcome == ^"rejected",
      where: not is_nil(sa.reviewed_at),
      where: sa.reviewed_at >= ^start_dt and sa.reviewed_at <= ^end_dt,
      preload: [user: u],
      order_by: [asc: sa.reviewed_at]
    )
    |> Repo.all()
  end

  defp list_expired(start_dt, end_dt) do
    from(s in Subscription,
      join: u in User,
      on: u.id == s.user_id,
      where: s.stripe_status in ["canceled", "unpaid"],
      where: not is_nil(s.current_period_end),
      where:
        s.current_period_end >= ^start_dt and s.current_period_end <= ^end_dt,
      preload: [user: u],
      order_by: [asc: s.current_period_end]
    )
    |> Repo.all()
  end

  defp list_purchased(start_dt, end_dt) do
    from(s in Subscription,
      join: u in User,
      on: u.id == s.user_id,
      where: s.stripe_status in ["active", "trialing"],
      where: not is_nil(s.start_date),
      where: s.start_date >= ^start_dt and s.start_date <= ^end_dt,
      preload: [user: u],
      order_by: [asc: s.start_date]
    )
    |> Repo.all()
  end

  # Attaches each user's SignupApplication (if any) to their subscription struct
  # so the report page can show application details for purchased memberships.
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
