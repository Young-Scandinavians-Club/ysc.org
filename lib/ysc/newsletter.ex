defmodule Ysc.Newsletter do
  @moduledoc """
  Context for managing newsletter subscriptions.

  Handles subscribe/unsubscribe for both authenticated users and anonymous
  signups. When a user who previously signed up anonymously later creates
  an account, the existing subscription record is updated (linked) rather
  than duplicated.
  """
  require Ysc.Logging

  import Ecto.Query

  alias Ysc.Repo
  alias Ysc.Email.Suppression
  alias Ysc.Newsletter.Subscriber
  alias Ysc.Accounts.Email
  alias Ysc.Newsletter.Edition
  alias Ysc.Newsletter.EmailEvent
  alias Ysc.Newsletter.Notice
  alias Ysc.Newsletter.UnsubscribeEvent
  alias Ysc.Messages.MessageIdempotency
  alias Ysc.Events.Event
  alias Ysc.Posts.Post

  @editions_topic "newsletter_editions"

  @doc """
  Subscribes the calling process to edition lifecycle broadcasts.

  Broadcasted messages: `{:edition_delivery_progress, %Edition{}}` and
  `{:edition_sent, %Edition{}}`.
  """
  def subscribe_to_edition_updates do
    Phoenix.PubSub.subscribe(Ysc.PubSub, @editions_topic)
  end

  @doc """
  Broadcasts that an edition has been sent to all subscribers.
  """
  def broadcast_edition_sent(%Edition{} = edition) do
    Phoenix.PubSub.broadcast(
      Ysc.PubSub,
      @editions_topic,
      {:edition_sent, preload_edition_creator(edition)}
    )
  end

  @doc false
  def broadcast_edition_delivery_progress(%Edition{} = edition) do
    Phoenix.PubSub.broadcast(
      Ysc.PubSub,
      @editions_topic,
      {:edition_delivery_progress, preload_edition_creator(edition)}
    )
  end

  defp preload_edition_creator(%Edition{} = edition) do
    if Ecto.assoc_loaded?(edition.creator),
      do: edition,
      else: Repo.preload(edition, :creator)
  end

  # Fields fetched in list queries — excludes :archived_html (large text).
  # Use get_edition!/1 or get_sent_edition/1 when the full record is needed.
  @edition_list_fields [
    :id,
    :title,
    :subject,
    :intro_text,
    :status,
    :post_ids,
    :event_ids,
    :sent_at,
    :sent_count,
    :scheduled_at,
    :cover_image_id,
    :creator_id,
    :inserted_at,
    :updated_at
  ]

  @doc """
  Subscribes an email to the newsletter.

  If the email already exists:
  - Updates the record (e.g. re-activates if previously unsubscribed).
  - If opts include user_id and the existing record has no user_id, links
    the subscription to the user (source becomes "user_registration_linked").

  Options:
  - :user_id - Link to a user (for authenticated subscriptions)
  - :first_name, :last_name - Optional names
  - :source - Source of subscription (e.g. "public_signup", "user_registration")
  - :metadata - Map of extra data
  - :subscribed_at - Optional historical subscription time (new subscribers only)
  - :skip_email_validation - When true, skip MX/disposable checks (trusted imports)

  Returns `{:ok, subscriber}` or `{:error, changeset}` or `{:error, atom}`.

  Error atoms:
  - `:invalid_email` - malformed email address
  - `:no_mx_records` - domain cannot receive email
  - `:disposable_email` - throwaway/temporary email domain blocked
  """
  def subscribe(email, opts \\ [])

  def subscribe(email, opts) when is_binary(email) do
    email
    |> String.trim()
    |> Email.normalize()
    |> subscribe_normalized(opts)
  end

  def subscribe(_email, _opts), do: {:error, :invalid_email}

  defp subscribe_normalized(email, opts) when is_binary(email) do
    if Keyword.get(opts, :skip_email_validation, false) do
      do_subscribe(email, opts)
    else
      case Ysc.Newsletter.EmailValidator.validate_email(email) do
        :ok -> do_subscribe(email, opts)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp do_subscribe(email, opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    user_id = Keyword.get(opts, :user_id)
    first_name = Keyword.get(opts, :first_name)
    last_name = Keyword.get(opts, :last_name)
    source = Keyword.get(opts, :source, "public_signup")
    metadata = Keyword.get(opts, :metadata, %{})
    subscribed_at = Keyword.get(opts, :subscribed_at) || now

    case get_subscriber_by_email(email) do
      nil ->
        create_subscriber(
          email,
          subscribed_at,
          user_id,
          first_name,
          last_name,
          source,
          metadata
        )

      existing ->
        update_existing_subscriber(existing, subscribed_at, email, opts)
    end
  end

  defp create_subscriber(
         email,
         subscribed_at,
         user_id,
         first_name,
         last_name,
         source,
         metadata
       ) do
    token = Subscriber.generate_subscription_token()

    %Subscriber{}
    |> Subscriber.create_changeset(%{
      email: email,
      user_id: user_id,
      first_name: first_name,
      last_name: last_name,
      subscribed: true,
      subscription_token: token,
      # This is a trusted/immediate subscribe path (authenticated toggle,
      # admin, CSV import, etc.) — auto-confirm so `confirmed_at IS NULL`
      # remains a reliable signal exclusively for double opt-in pending rows.
      confirmed_at: subscribed_at,
      source: source,
      metadata: metadata,
      subscribed_at: subscribed_at,
      unsubscribed_at: nil
    })
    |> Repo.insert()
  end

  defp update_existing_subscriber(existing, subscribed_at, email, opts) do
    user_id = Keyword.get(opts, :user_id)
    first_name = Keyword.get(opts, :first_name)
    last_name = Keyword.get(opts, :last_name)
    source = Keyword.get(opts, :source, "public_signup")
    metadata = Keyword.get(opts, :metadata, %{})
    force_source = Keyword.get(opts, :force_source, false)

    # If we now have a user_id but existing record doesn't, link them
    link_user = user_id && is_nil(existing.user_id)

    new_source =
      cond do
        link_user -> "user_registration_linked"
        force_source -> source
        existing.subscribed -> existing.source || source
        true -> source
      end

    attrs = %{
      email: email,
      subscribed: true,
      unsubscribed_at: nil,
      source: new_source,
      # Trusted/immediate subscribe path — auto-confirm (see create_subscriber/7).
      confirmed_at: existing.confirmed_at || subscribed_at,
      metadata: Map.merge(existing.metadata || %{}, metadata)
    }

    attrs =
      attrs
      |> maybe_put(:user_id, user_id || existing.user_id)
      |> maybe_put(:first_name, first_name || existing.first_name)
      |> maybe_put(:last_name, last_name || existing.last_name)

    # Preserve original subscribed_at when already subscribed; otherwise use
    # the provided time (CSV historical date or "now" from the caller).
    attrs =
      if existing.subscribed,
        do: attrs,
        else: Map.put(attrs, :subscribed_at, subscribed_at)

    existing
    |> Subscriber.update_changeset(attrs)
    |> Repo.update()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp find_subscriber_by_canonical_email(normalized_email) do
    if Email.gmail?(normalized_email) do
      [_local, domain] = String.split(normalized_email, "@", parts: 2)

      from(s in Subscriber, where: ilike(s.email, ^"%@#{domain}"))
      |> Repo.all()
      |> Enum.find(fn subscriber ->
        Email.normalize(subscriber.email) == normalized_email
      end)
    else
      nil
    end
  end

  @doc """
  Requests a double opt-in confirmation for an anonymous newsletter signup.

  Unlike `subscribe/2`, this does NOT add the email to the active list.
  Instead it stores a pending subscriber record (creating one, or rotating
  the confirmation token on an existing not-yet-confirmed record) and sends
  a confirmation email. The address only becomes an active subscriber once
  `confirm_subscription/1` is called with the emailed token.

  A 24-hour reminder email is also scheduled, and is skipped at send time if
  the subscriber has since confirmed or been removed.

  Options:
  - :source - Source of subscription (e.g. "public_signup")
  - :metadata - Map of extra data

  Returns:
  - `{:ok, :pending}` - a confirmation email was sent (or resent)
  - `{:ok, :already_subscribed}` - the email is already an active, confirmed
    subscriber; no email sent (avoids duplicate emails / enumeration)
  - `{:error, changeset}` or `{:error, atom}` - same error shapes as `subscribe/2`
  """
  def request_confirmation(email, opts \\ [])

  def request_confirmation(email, opts) when is_binary(email) do
    email
    |> String.trim()
    |> Email.normalize()
    |> request_confirmation_normalized(opts)
  end

  def request_confirmation(_email, _opts), do: {:error, :invalid_email}

  defp request_confirmation_normalized(email, opts) do
    case Ysc.Newsletter.EmailValidator.validate_email(email) do
      :ok -> do_request_confirmation(email, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_request_confirmation(email, opts) do
    source = Keyword.get(opts, :source, "public_signup")
    metadata = Keyword.get(opts, :metadata, %{})

    case get_subscriber_by_email(email) do
      nil ->
        email
        |> create_pending_subscriber(source, metadata)
        |> after_pending_write()

      %Subscriber{subscribed: true, confirmed_at: confirmed_at}
      when not is_nil(confirmed_at) ->
        {:ok, :already_subscribed}

      existing ->
        existing
        |> reactivate_pending_subscriber(source, metadata)
        |> after_pending_write()
    end
  end

  defp after_pending_write({:ok, %Subscriber{} = subscriber}) do
    send_confirmation_email(subscriber)
    schedule_confirmation_reminder(subscriber)
    {:ok, :pending}
  end

  defp after_pending_write({:error, _reason} = error), do: error

  defp create_pending_subscriber(email, source, metadata) do
    %Subscriber{}
    |> Subscriber.create_changeset(%{
      email: email,
      subscribed: false,
      subscription_token: Subscriber.generate_subscription_token(),
      confirmation_token: Subscriber.generate_confirmation_token(),
      confirmed_at: nil,
      source: source,
      metadata: metadata,
      subscribed_at: nil,
      unsubscribed_at: nil
    })
    |> Repo.insert()
  end

  defp reactivate_pending_subscriber(existing, source, metadata) do
    attrs = %{
      confirmation_token: Subscriber.generate_confirmation_token(),
      source: existing.source || source,
      metadata: Map.merge(existing.metadata || %{}, metadata)
    }

    existing
    |> Subscriber.update_changeset(attrs)
    |> Repo.update()
  end

  defp send_confirmation_email(%Subscriber{} = subscriber, opts \\ []) do
    reminder = Keyword.get(opts, :reminder, false)

    subject =
      if reminder,
        do: "Just checking in — please confirm your subscription",
        else: "Action Required: Please confirm your subscription"

    url =
      YscWeb.Emails.Helpers.absolute_url(
        "/newsletter/confirm/#{subscriber.confirmation_token}"
      )

    idempotency_key =
      if reminder,
        do: "newsletter_confirmation_reminder_#{subscriber.id}",
        else:
          "newsletter_confirmation_#{subscriber.id}_#{subscriber.confirmation_token}"

    case YscWeb.Emails.Notifier.schedule_email(
           subscriber.email,
           idempotency_key,
           subject,
           "newsletter_confirmation",
           %{url: url, reminder: reminder},
           ""
         ) do
      {:error, reason} ->
        Ysc.Logging.warning("Newsletter: failed to schedule confirmation email",
          subscriber_id: subscriber.id,
          reminder: reminder,
          error: inspect(reason)
        )

        :ok

      _job ->
        :ok
    end
  end

  defp schedule_confirmation_reminder(%Subscriber{} = subscriber) do
    case YscWeb.Workers.NewsletterConfirmationReminder.schedule(subscriber.id) do
      {:ok, %Oban.Job{}} ->
        :ok

      {:error, reason} ->
        Ysc.Logging.warning(
          "Newsletter: failed to schedule confirmation reminder",
          subscriber_id: subscriber.id,
          error: inspect(reason)
        )

        :ok
    end
  end

  @doc """
  Sends a reminder confirmation email for a still-pending subscriber.

  Called by `YscWeb.Workers.NewsletterConfirmationReminder`, 24 hours after
  `request_confirmation/2` scheduled it. No-ops if the subscriber no longer
  exists or has already confirmed since scheduling (covers both a completed
  confirmation and an unsubscribe/removal in the meantime).
  """
  def deliver_confirmation_reminder(subscriber_id) do
    case Repo.get(Subscriber, subscriber_id) do
      nil ->
        :ok

      %Subscriber{confirmed_at: confirmed_at} when not is_nil(confirmed_at) ->
        :ok

      subscriber ->
        send_confirmation_email(subscriber, reminder: true)
    end
  end

  @doc """
  Confirms a pending double opt-in subscription using the emailed token.

  Idempotent: replaying the same link after it has already been confirmed
  returns the subscriber unchanged rather than erroring, so reloading the
  confirmation page is always safe.

  Returns `{:ok, subscriber}` or `{:error, :not_found}`.
  """
  def confirm_subscription(token) when is_binary(token) do
    case Repo.get_by(Subscriber, confirmation_token: token) do
      nil ->
        {:error, :not_found}

      %Subscriber{confirmed_at: confirmed_at} = subscriber
      when not is_nil(confirmed_at) ->
        {:ok, subscriber}

      subscriber ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        subscriber
        |> Subscriber.update_changeset(%{
          subscribed: true,
          confirmed_at: now,
          subscribed_at: now,
          unsubscribed_at: nil
        })
        |> Repo.update()
    end
  end

  def confirm_subscription(_token), do: {:error, :not_found}

  @doc """
  Unsubscribes by email or by subscription token.

  Options:
  - `:edition_id` — when present and valid, records a confirmed
    `UnsubscribeEvent` attributed to that edition (idempotent per
    edition/subscriber pair).

  Returns `{:ok, subscriber}` or `{:error, :not_found}`.
  """
  def unsubscribe(email_or_token, opts \\ [])
      when is_binary(email_or_token) and is_list(opts) do
    edition_id = Keyword.get(opts, :edition_id)

    cond do
      String.contains?(email_or_token, "@") ->
        unsubscribe_by_email(email_or_token, edition_id)

      true ->
        unsubscribe_by_token(email_or_token, edition_id)
    end
  end

  defp unsubscribe_by_email(email, edition_id) do
    case get_subscriber_by_email(email) do
      nil -> {:error, :not_found}
      subscriber -> do_unsubscribe(subscriber, edition_id)
    end
  end

  defp unsubscribe_by_token(token, edition_id) do
    case get_subscriber_by_token(token) do
      nil -> {:error, :not_found}
      subscriber -> do_unsubscribe(subscriber, edition_id)
    end
  end

  defp do_unsubscribe(subscriber, edition_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case subscriber
         |> Subscriber.update_changeset(%{
           subscribed: false,
           unsubscribed_at: now
         })
         |> Repo.update() do
      {:ok, updated} ->
        maybe_record_unsubscribe_event(updated, edition_id, now)
        {:ok, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_record_unsubscribe_event(_subscriber, edition_id, _now)
       when not is_binary(edition_id) or edition_id == "",
       do: :ok

  defp maybe_record_unsubscribe_event(subscriber, edition_id, now) do
    if edition_exists?(edition_id) do
      result =
        try do
          %UnsubscribeEvent{}
          |> UnsubscribeEvent.changeset(%{
            edition_id: edition_id,
            subscriber_id: subscriber.id,
            unsubscribed_at: now
          })
          |> Repo.insert(
            on_conflict: :nothing,
            conflict_target: [:edition_id, :subscriber_id]
          )
        rescue
          error ->
            Ysc.Logging.error(
              "Newsletter: failed to record unsubscribe event",
              error: error,
              stacktrace: __STACKTRACE__,
              extra: %{
                edition_id: edition_id,
                subscriber_id: subscriber.id
              }
            )

            {:error, :insert_failed}
        end

      case result do
        {:ok, _} ->
          :ok

        {:error, %Ecto.Changeset{} = changeset} ->
          Ysc.Logging.warning(
            "Newsletter: unsubscribe event changeset invalid",
            edition_id: edition_id,
            subscriber_id: subscriber.id,
            errors: inspect(changeset.errors)
          )

          :ok

        {:error, _reason} ->
          :ok
      end
    else
      :ok
    end
  end

  defp edition_exists?(edition_id) when is_binary(edition_id) do
    valid_ulid?(edition_id) and
      Repo.exists?(from(e in Edition, where: e.id == ^edition_id))
  end

  @doc """
  Returns the subscriber for the given email, or nil.
  """
  def get_subscriber_by_email(email) when is_binary(email) do
    normalized_email = Email.normalize(email)

    case Repo.get_by(Subscriber, email: normalized_email) do
      %Subscriber{} = subscriber ->
        subscriber

      nil ->
        find_subscriber_by_canonical_email(normalized_email)
    end
  end

  @doc """
  Returns the subscriber for the given subscription token, or nil.
  """
  def get_subscriber_by_token(token) when is_binary(token) do
    Repo.get_by(Subscriber, subscription_token: token)
  end

  @doc """
  Syncs the newsletter_subscribers table with the given newsletter preference.

  If `newsletter_subscribed` is true, subscribes the user's email (or links
  existing subscription). If false, unsubscribes their email.

  Options:
  - :newsletter_subscribed - boolean, whether the user wants to receive the newsletter
  """
  def sync_user_preference(user, opts) do
    subscribed = Keyword.fetch!(opts, :newsletter_subscribed)

    if subscribed do
      case subscribe(user.email,
             user_id: user.id,
             first_name: user.first_name,
             last_name: user.last_name,
             source: "user_settings"
           ) do
        {:ok, _} ->
          :ok

        {:error, changeset} ->
          Ysc.Logging.warning("Newsletter sync: failed to subscribe",
            user_id: user.id,
            errors: inspect(changeset.errors)
          )

          :ok
      end
    else
      case unsubscribe(user.email) do
        {:ok, _} -> :ok
        {:error, :not_found} -> :ok
        {:error, _} -> :ok
      end
    end
  end

  @doc """
  Lists subscribers with optional filters.

  Options:
  - :subscribed - boolean, filter by subscribed (true = only active)
  - :source - string, filter by source
  """
  def list_subscribers(opts \\ []) do
    Subscriber
    |> maybe_filter_subscribed(opts)
    |> maybe_filter_source(opts)
    |> Repo.all()
  end

  @doc """
  Counts subscribers matching the same filters as `list_subscribers/1`.

  Uses a single aggregate query instead of loading every matching row.
  """
  def count_subscribers(opts \\ []) do
    Subscriber
    |> maybe_filter_subscribed(opts)
    |> maybe_filter_source(opts)
    |> select([s], count(s.id))
    |> Repo.one()
  end

  defp maybe_filter_subscribed(query, opts) do
    case Keyword.get(opts, :subscribed) do
      true -> where(query, [s], s.subscribed == true)
      false -> where(query, [s], s.subscribed == false)
      _ -> query
    end
  end

  defp maybe_filter_source(query, opts) do
    case Keyword.get(opts, :source) do
      nil -> query
      source -> where(query, [s], s.source == ^source)
    end
  end

  @doc """
  Lists subscribers with Flop pagination, sorting, and filtering.

  Params are passed through to Flop (page, limit, order, filters).
  Filterable: email, subscribed. Sortable: email, inserted_at, subscribed_at.
  """
  def list_paginated_subscribers(params) do
    base_query =
      Subscriber
      |> Ecto.Query.exclude(:order_by)

    case Flop.validate_and_run(base_query, params, for: Subscriber) do
      {:ok, {subscribers, meta}} -> {:ok, {subscribers, meta}}
      error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Newsletter editions (curated content: cover, intro, posts, events)
  # ---------------------------------------------------------------------------

  @doc """
  Lists all newsletter editions, newest first.
  """
  def list_editions do
    Edition
    |> order_by([e], desc: e.inserted_at)
    |> select([e], struct(e, ^@edition_list_fields))
    |> Repo.all()
    |> Repo.preload([:cover_image, :creator])
  end

  @doc """
  Lists newsletter editions with Flop pagination, sorting, and filtering.

  Options:
  - :date_from - filter by inserted_at >= date (YYYY-MM-DD)
  - :date_to - filter by inserted_at <= date (YYYY-MM-DD)
  """
  def list_paginated_editions(params, opts \\ []) do
    date_from = Keyword.get(opts, :date_from, "")
    date_to = Keyword.get(opts, :date_to, "")

    base_query =
      Edition
      |> select([e], struct(e, ^@edition_list_fields))
      |> preload([:cover_image, :creator])
      |> Ecto.Query.exclude(:order_by)
      |> maybe_filter_inserted_at_from(date_from)
      |> maybe_filter_inserted_at_to(date_to)

    case Flop.validate_and_run(base_query, params, for: Edition) do
      {:ok, {editions, meta}} -> {:ok, {editions, meta}}
      error -> error
    end
  end

  defp maybe_filter_inserted_at_from(query, ""), do: query

  defp maybe_filter_inserted_at_from(query, date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        datetime = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
        where(query, [e], e.inserted_at >= ^datetime)

      _ ->
        query
    end
  end

  defp maybe_filter_inserted_at_to(query, ""), do: query

  defp maybe_filter_inserted_at_to(query, date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        datetime = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
        where(query, [e], e.inserted_at <= ^datetime)

      _ ->
        query
    end
  end

  @doc """
  Returns a list of {display_name, creator_id} for all users who have created
  at least one newsletter edition (for filter dropdowns).
  """
  def get_all_creators do
    from(
      e in Edition,
      left_join: u in assoc(e, :creator),
      distinct: e.creator_id,
      select: %{
        "creator_id" => e.creator_id,
        "creator_first" => u.first_name,
        "creator_last" => u.last_name,
        "creator_email" => u.email
      },
      order_by: [asc: u.first_name, asc: u.last_name]
    )
    |> Repo.all()
    |> format_creators()
  end

  defp format_creators(result) do
    result
    |> Enum.map(fn entry ->
      name = creator_display_name(entry)
      {name, entry["creator_id"]}
    end)
  end

  defp creator_display_name(%{"creator_first" => first, "creator_last" => last})
       when is_binary(first) and is_binary(last) do
    "#{String.capitalize(first)} #{String.downcase(last)}"
  end

  defp creator_display_name(%{"creator_email" => email}) when is_binary(email),
    do: email

  defp creator_display_name(_), do: "Unknown"

  @doc """
  Gets a single edition by id. Raises if not found.
  """
  def get_edition!(id),
    do: Repo.get!(Edition, id) |> Repo.preload([:cover_image, :creator])

  @doc """
  Lists all sent editions, most recently sent first.

  Excludes archived_html to keep list queries lean.
  """
  def list_sent_editions do
    from(e in Edition,
      where: e.status == :sent,
      order_by: [desc: e.sent_at],
      select: struct(e, ^@edition_list_fields)
    )
    |> Repo.all()
  end

  @doc """
  Returns a single sent edition by id, including archived_html.

  Returns nil if the edition does not exist or has not been sent.
  """
  def get_sent_edition(id) do
    Repo.get_by(Edition, id: id, status: :sent)
  end

  @doc """
  Stores the de-personalized archived HTML for a sent edition.
  """
  def store_archive_html(%Edition{} = edition, html) when is_binary(html) do
    edition
    |> Ecto.Changeset.change(%{archived_html: html})
    |> Repo.update()
  end

  @doc """
  Creates a new newsletter edition (draft).

  Options:
  - :created_by_id - user id of the admin creating the edition (required to record creator)
  """
  def create_edition(attrs \\ %{}, opts \\ []) do
    attrs = Map.put_new(attrs, "status", :draft)
    creator_id = Keyword.get(opts, :created_by_id)

    %Edition{}
    |> Edition.changeset(attrs)
    |> maybe_put_creator(creator_id)
    |> Repo.insert()
  end

  @doc """
  Creates a newsletter edition from editor draft fields only.

  Strips forged lifecycle params (`status`, `sent_at`, etc.) from LiveView saves.
  """
  def create_edition_draft(attrs \\ %{}, opts \\ []) do
    creator_id = Keyword.get(opts, :created_by_id)

    %Edition{}
    |> Edition.draft_changeset(attrs)
    |> Ecto.Changeset.put_change(:status, :draft)
    |> maybe_put_creator(creator_id)
    |> Repo.insert()
  end

  defp maybe_put_creator(changeset, nil), do: changeset

  defp maybe_put_creator(changeset, creator_id),
    do: Ecto.Changeset.put_change(changeset, :creator_id, creator_id)

  @doc """
  Updates an edition.
  """
  def update_edition(%Edition{} = edition, attrs) do
    edition
    |> Edition.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Persists and broadcasts delivery progress for a sending newsletter edition.

  The recipient count is set only once, when the sender loads its recipients.
  Accepted deliveries are counted from the durable email delivery ledger.
  """
  def record_edition_delivery_progress(%Edition{} = edition, subscribers)
      when is_list(subscribers) do
    delivery_keys =
      Enum.map(subscribers, fn subscriber ->
        "newsletter_#{edition.id}_#{subscriber.id}"
      end)

    accepted_count =
      from(m in MessageIdempotency,
        where:
          m.message_type == :email and
            m.message_template == "newsletter_edition" and
            m.delivery_status == :accepted and
            m.idempotency_key in ^delivery_keys,
        select: count(m.id)
      )
      |> Repo.one()

    attrs =
      %{sent_count: accepted_count}
      |> maybe_put_recipient_count(edition, length(subscribers))

    case update_edition(edition, attrs) do
      {:ok, updated_edition} ->
        broadcast_edition_delivery_progress(updated_edition)
        {:ok, updated_edition}

      {:error, _reason} = error ->
        error
    end
  end

  defp maybe_put_recipient_count(
         attrs,
         %Edition{recipient_count: nil},
         recipient_count
       ),
       do: Map.put(attrs, :recipient_count, recipient_count)

  defp maybe_put_recipient_count(attrs, %Edition{}, _recipient_count), do: attrs

  @doc false
  def subscribers_needing_newsletter_delivery(%Edition{} = edition, subscribers)
      when is_list(subscribers) do
    delivery_keys =
      Enum.map(subscribers, fn subscriber ->
        "newsletter_#{edition.id}_#{subscriber.id}"
      end)

    accepted_keys =
      from(m in MessageIdempotency,
        where:
          m.message_type == :email and
            m.message_template == "newsletter_edition" and
            m.delivery_status == :accepted and
            m.idempotency_key in ^delivery_keys,
        select: m.idempotency_key
      )
      |> Repo.all()
      |> MapSet.new()

    Enum.reject(subscribers, fn subscriber ->
      MapSet.member?(accepted_keys, "newsletter_#{edition.id}_#{subscriber.id}")
    end)
  end

  @doc """
  Updates editorial newsletter fields from the admin editor draft save path.
  """
  def update_edition_draft(%Edition{} = edition, attrs) do
    edition
    |> Edition.draft_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an edition.

  Returns `{:error, :already_sent}` if the edition has already been sent — sent
  editions are preserved as archive records and cannot be destroyed.
  """
  def delete_edition(%Edition{status: :sent}), do: {:error, :already_sent}

  def delete_edition(%Edition{} = edition) do
    Repo.delete(edition)
  end

  @doc """
  Duplicates an edition into a new draft.

  Copies editorial fields (`title`, `subject`, `intro_text`, `cover_image_id`,
  `post_ids`, `event_ids`). Appends `" (copy)"` to the title (truncated to 255).
  Lifecycle fields are reset: status `:draft`, no schedule/send/archive data.

  Options:
  - `:created_by_id` — user id recorded as the new draft's creator
  """
  def duplicate_edition(%Edition{} = edition, opts \\ []) do
    creator_id = Keyword.get(opts, :created_by_id)
    title = duplicate_edition_title(edition.title)

    attrs = %{
      "title" => title,
      "subject" => edition.subject || "",
      "intro_text" => edition.intro_text,
      "cover_image_id" => edition.cover_image_id,
      "post_ids" => edition.post_ids || [],
      "event_ids" => edition.event_ids || []
    }

    create_edition_draft(attrs, created_by_id: creator_id)
  end

  defp duplicate_edition_title(title) when is_binary(title) do
    suffix = " (copy)"
    max_base = 255 - String.length(suffix)

    title
    |> String.trim()
    |> then(fn t -> if t == "", do: "Untitled", else: t end)
    |> String.slice(0, max_base)
    |> Kernel.<>(suffix)
  end

  defp duplicate_edition_title(_), do: "Untitled (copy)"

  # ---------------------------------------------------------------------------
  # Saved notices
  # ---------------------------------------------------------------------------

  @doc """
  Lists all saved notices, newest first.
  """
  def list_notices do
    from(n in Notice, order_by: [desc: n.updated_at], preload: [:creator])
    |> Repo.all()
  end

  @doc false
  def list_notices_query do
    from(n in Notice, order_by: [desc: n.updated_at], preload: [:creator])
  end

  @doc """
  Gets a single notice by id. Raises if not found.
  """
  def get_notice!(id),
    do: Repo.get!(Notice, id) |> Repo.preload(:creator)

  @doc """
  Creates a saved notice.

  Options:
  - `:created_by_id` — user id recorded as creator
  """
  def create_notice(attrs \\ %{}, opts \\ []) do
    creator_id = Keyword.get(opts, :created_by_id)

    %Notice{}
    |> Notice.changeset(attrs)
    |> maybe_put_notice_creator(creator_id)
    |> Repo.insert()
  end

  @doc """
  Updates a saved notice.
  """
  def update_notice(%Notice{} = notice, attrs) do
    notice
    |> Notice.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a saved notice.
  """
  def delete_notice(%Notice{} = notice) do
    Repo.delete(notice)
  end

  defp maybe_put_notice_creator(changeset, nil), do: changeset

  defp maybe_put_notice_creator(changeset, creator_id),
    do: Ecto.Changeset.put_change(changeset, :creator_id, creator_id)

  @doc """
  Enqueues sending of the newsletter to all subscribed subscribers.

  Works for both `:draft` and `:scheduled` editions. Sending a scheduled edition
  cancels the intent of the existing scheduled Oban job — the previously queued
  job will run but `NewsletterSender` checks for `:sent` status and skips it
  safely.

  Returns `{:error, :already_sent}` if the edition is already sending or sent.
  Returns `{:ok, sending_edition}` on success so callers have the updated struct.
  """
  def send_edition(%Edition{} = edition) do
    if edition.status in [:sending, :sent] do
      {:error, :already_sent}
    else
      with {:ok, sending_edition} <-
             update_edition(edition, %{status: :sending}),
           {:ok, _job} <-
             %{edition_id: edition.id}
             |> YscWeb.Workers.NewsletterSender.new()
             |> Oban.insert() do
        {:ok, preload_edition_creator(sending_edition)}
      else
        {:error, %Ecto.Changeset{}} = err ->
          err

        {:error, reason} ->
          # Oban insert failed — revert status so the edition is not stuck in :sending
          update_edition(edition, %{status: edition.status})
          {:error, reason}
      end
    end
  end

  @doc """
  Sends a one-off test copy of the edition to `user`.

  Renders the email using the user's first name and a placeholder unsubscribe
  URL. Does not change the edition's status or sent_count.
  """
  def send_test_email(%Edition{} = edition, user) do
    alias Ysc.Posts
    alias Ysc.Events
    alias Ysc.Messages
    alias YscWeb.Emails.NewsletterEdition

    edition = Repo.preload(edition, :cover_image)

    posts = Posts.list_posts_by_ids(edition.post_ids || [], [:featured_image])

    events =
      Events.list_events_by_ids(edition.event_ids || [],
        preloads: [:cover_image, :ticket_tiers]
      )

    fake_subscriber = %{
      first_name: user.first_name || "there",
      email: user.email,
      subscription_token: nil
    }

    assigns =
      NewsletterEdition.build_assigns(edition, fake_subscriber, posts, events)

    html = NewsletterEdition.render(assigns)

    subject = "[YSC] [TEST] #{edition.subject || edition.title}"

    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to(user.email)
      |> Swoosh.Email.from(
        {Ysc.EmailConfig.from_name(), Ysc.EmailConfig.from_email()}
      )
      |> Swoosh.Email.subject(subject)
      |> Swoosh.Email.html_body(html)

    idempotency_key =
      "newsletter_test_#{edition.id}_#{user.id}_#{System.unique_integer([:positive])}"

    attrs = %{
      message_type: :email,
      idempotency_key: idempotency_key,
      message_template: "newsletter_edition",
      params: %{edition_id: edition.id, test: true},
      email: user.email,
      user_id: user.id,
      rendered_message: html,
      edition_id: edition.id
    }

    case Messages.run_send_message_idempotent(email, attrs) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Schedules the edition to be sent at the given UTC datetime.

  Persists `scheduled_at` and status `:scheduled`, then enqueues a
  `NewsletterSender` Oban job with `scheduled_at` so Oban fires it at the
  correct time automatically — no separate cron worker is required.
  """
  def schedule_edition(%Edition{} = edition, scheduled_at)
      when is_struct(scheduled_at, DateTime) do
    # Update the edition status first, then schedule the Oban job outside any
    # transaction. This matches the production behaviour where the worker picks
    # up the job after the transaction has committed and uses its own connection.
    # It also prevents the Inline test engine from executing the sender while the
    # transaction's connection is still held, which would deadlock task processes.
    with {:ok, updated} <-
           update_edition(edition, %{
             scheduled_at: scheduled_at,
             status: :scheduled
           }) do
      %{edition_id: updated.id}
      |> YscWeb.Workers.NewsletterSender.new(scheduled_at: scheduled_at)
      |> Oban.insert!()

      {:ok, updated}
    end
  end

  # ---------------------------------------------------------------------------
  # Email event tracking (SES opens, clicks, bounces, complaints)
  # ---------------------------------------------------------------------------

  @doc """
  Records an SES email event (open, click, bounce, complaint) in the database.

  Returns `{:ok, event}` or `{:error, changeset}`.
  """
  def record_email_event(attrs) do
    %EmailEvent{}
    |> EmailEvent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Handles a hard bounce for the given email address.

  Unsubscribes the subscriber from the newsletter (if they exist and are
  currently subscribed) and records a note in their metadata. This prevents
  future newsletters from being sent to an address that is known to bounce.

  Returns `{:ok, subscriber}` if the subscriber was found and unsubscribed,
  `{:ok, :not_subscribed}` if no active subscription was found, or
  `{:error, changeset}` on update failure.
  """
  def handle_hard_bounce(email) when is_binary(email) do
    :ok = Suppression.suppress_hard_bounce(email)

    case get_subscriber_by_email(email) do
      nil ->
        {:ok, :not_subscribed}

      %Subscriber{subscribed: false} ->
        {:ok, :not_subscribed}

      subscriber ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        updated_metadata =
          Map.merge(subscriber.metadata || %{}, %{
            "hard_bounced_at" => DateTime.to_iso8601(now),
            "unsubscribe_reason" => "hard_bounce"
          })

        subscriber
        |> Subscriber.update_changeset(%{
          subscribed: false,
          unsubscribed_at: now,
          source: "hard_bounce",
          metadata: updated_metadata
        })
        |> Repo.update()
    end
  end

  @doc """
  Returns whether an email address has been suppressed after a hard bounce.

  Hard-bounce suppression applies to every email category, not only newsletters.
  """
  def hard_bounced?(email) when is_binary(email) do
    Suppression.hard_bounced?(email)
  end

  def hard_bounced?(_), do: false

  @doc """
  Returns email events for a given edition, ordered by most recent first.
  """
  def list_email_events_for_edition(edition_id) when is_binary(edition_id) do
    EmailEvent
    |> where([e], e.edition_id == ^edition_id)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns a summary count of email events grouped by type for a given edition.

  Opens and clicks are counted as unique recipients (distinct email) for
  meaningful engagement rates. Bounces and complaints use total event counts
  since they are delivery-level signals.

  Example return: `%{"open" => 42, "click" => 17, "bounce" => 3}`
  """
  def count_email_events_by_type(edition_id) when is_binary(edition_id) do
    unique_types = ["open", "click"]

    EmailEvent
    |> where([e], e.edition_id == ^edition_id)
    |> group_by([e], e.event_type)
    |> select([e], {
      e.event_type,
      fragment(
        "CASE WHEN ? = ANY(?) THEN COUNT(DISTINCT ?) ELSE COUNT(*) END",
        e.event_type,
        ^unique_types,
        e.email
      )
    })
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Lists recently sent newsletter editions with engagement counts for dashboards.

  Returns a list of maps: `%{edition: %Edition{}, opens: integer(), clicks: integer()}`.
  """
  def list_recent_sent_editions_with_stats(limit \\ 5)
      when is_integer(limit) and limit > 0 do
    editions =
      limit
      |> recent_sent_editions_query()
      |> Repo.all()

    edition_ids = Enum.map(editions, & &1.id)
    counts_by_edition = batch_open_click_counts_by_edition_ids(edition_ids)

    Enum.map(editions, fn edition ->
      counts =
        Map.get(counts_by_edition, engagement_counts_key(edition.id), %{
          opens: 0,
          clicks: 0
        })

      %{
        edition: edition,
        opens: counts.opens,
        clicks: counts.clicks
      }
    end)
  end

  @doc false
  def recent_sent_editions_query(limit \\ 5)
      when is_integer(limit) and limit > 0 do
    from(e in Edition,
      where: e.status == :sent,
      where: not is_nil(e.sent_at),
      order_by: [desc: e.sent_at],
      limit: ^limit,
      select: struct(e, ^@edition_list_fields)
    )
  end

  @doc false
  def recent_newsletter_open_click_counts_query(edition_ids \\ nil)

  def recent_newsletter_open_click_counts_query(nil) do
    recent_newsletter_open_click_counts_query([
      Ecto.ULID.generate(),
      Ecto.ULID.generate()
    ])
  end

  def recent_newsletter_open_click_counts_query(edition_ids)
      when is_list(edition_ids) do
    from(e in EmailEvent,
      where: e.edition_id in ^edition_ids,
      where: e.event_type in ["open", "click"],
      group_by: [e.edition_id, e.event_type],
      select: %{
        edition_id: e.edition_id,
        event_type: e.event_type,
        unique_recipients: fragment("COUNT(DISTINCT ?)", e.email)
      }
    )
  end

  defp batch_open_click_counts_by_edition_ids([]), do: %{}

  defp batch_open_click_counts_by_edition_ids(edition_ids) do
    edition_ids
    |> recent_newsletter_open_click_counts_query()
    |> Repo.all()
    |> Enum.reduce(%{}, fn row, acc ->
      key = engagement_counts_key(row.edition_id)
      count = row.unique_recipients
      prev = Map.get(acc, key, %{opens: 0, clicks: 0})

      next =
        case engagement_event_bucket(row.event_type) do
          :open -> %{prev | opens: count}
          :click -> %{prev | clicks: count}
          :ignore -> prev
        end

      Map.put(acc, key, next)
    end)
  end

  defp engagement_counts_key(id), do: to_string(id)

  defp engagement_event_bucket(event_type) do
    case event_type |> to_string() |> String.trim() do
      "open" -> :open
      "click" -> :click
      _ -> :ignore
    end
  end

  @doc """
  Counts unique recipients who clicked an unsubscribe link for an edition.

  Uses SES click events whose `link_url` contains `/newsletter/unsubscribe/`.
  This works for historical editions (no new tracking required).
  """
  def count_unsubscribe_link_clicks(edition_id) when is_binary(edition_id) do
    edition_id
    |> unsubscribe_link_clicks_query()
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc """
  Counts confirmed unsubscribes attributed to an edition.

  Only includes completions from email unsubscribe links that carried
  an `edition_id` (forward-looking; historical editions will show 0).
  """
  def count_confirmed_unsubscribes(edition_id) when is_binary(edition_id) do
    edition_id
    |> confirmed_unsubscribes_query()
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc """
  Returns total click counts per link URL for a given edition,
  sorted by most clicked first, with resolved titles for event and post URLs.

  Bare base-URL clicks (e.g. "https://ysc.org" or "https://ysc.org/") and
  unsubscribe links are excluded — unsubscribe engagement is reported
  separately via `count_unsubscribe_link_clicks/1`.

  Each entry is a map:
    %{url: url, clicks: n, title: "Event/Post title" | nil, type: :event | :post | :other}
  """
  def count_clicks_by_link(edition_id) when is_binary(edition_id) do
    base_url = String.trim_trailing(YscWeb.Endpoint.url(), "/")
    unsubscribe_pattern = unsubscribe_link_like_pattern()

    raw =
      EmailEvent
      |> where([e], e.edition_id == ^edition_id and e.event_type == "click")
      |> where([e], not is_nil(e.link_url))
      |> where(
        [e],
        e.link_url != ^base_url and e.link_url != ^(base_url <> "/")
      )
      |> where([e], not like(e.link_url, ^unsubscribe_pattern))
      |> group_by([e], e.link_url)
      |> select([e], {e.link_url, count(e.id)})
      |> order_by([e], desc: count(e.id))
      |> Repo.all()

    classified =
      Enum.map(raw, fn {url, clicks} ->
        {type, id_or_slug} = classify_link(url, base_url)
        {url, clicks, type, id_or_slug}
      end)

    event_ids =
      for {_url, _clicks, :event, id} <- classified, do: id

    post_identifiers =
      for {_url, _clicks, :post, id_or_slug} <- classified, do: id_or_slug

    event_titles =
      if event_ids == [] do
        %{}
      else
        Repo.all(
          from e in Event, where: e.id in ^event_ids, select: {e.id, e.title}
        )
        |> Map.new()
      end

    post_titles =
      if post_identifiers == [] do
        %{}
      else
        # Split identifiers so each `in` clause only receives values of the
        # matching column type — mixing slugs into the ULID-typed `id` binding
        # raises an Ecto.Query.CastError at runtime.
        {post_ids, post_slugs} =
          Enum.split_with(post_identifiers, &valid_ulid?/1)

        rows =
          Repo.all(
            from p in Post,
              where: p.id in ^post_ids or p.url_name in ^post_slugs,
              select: {p.id, p.url_name, p.title}
          )

        Enum.reduce(rows, %{}, fn {id, url_name, title}, acc ->
          acc
          |> Map.put(id, title)
          |> Map.put(url_name, title)
        end)
      end

    Enum.map(classified, fn {url, clicks, type, id_or_slug} ->
      title =
        case type do
          :event -> Map.get(event_titles, id_or_slug)
          :post -> Map.get(post_titles, id_or_slug)
          _ -> nil
        end

      %{url: url, clicks: clicks, title: title, type: type}
    end)
  end

  @doc """
  Returns true when `value` is a 26-character Crockford base-32 ULID string.
  """
  def valid_ulid?(value) when is_binary(value),
    do: String.match?(value, ~r/^[0-9A-HJKMNP-TV-Z]{26}$/i)

  def valid_ulid?(_), do: false

  # Match absolute or relative unsubscribe paths (with or without query string).
  @unsubscribe_link_like_pattern "%newsletter/unsubscribe%"

  defp unsubscribe_link_like_pattern, do: @unsubscribe_link_like_pattern

  defp classify_link(url, base_url) do
    path =
      url
      |> String.trim_leading(base_url)
      |> String.trim_leading("/")

    cond do
      match = Regex.run(~r{^events/([^/?#]+)}, path) ->
        [_, id] = match
        {:event, id}

      match = Regex.run(~r{^posts/([^/?#]+)}, path) ->
        [_, id_or_slug] = match
        {:post, id_or_slug}

      true ->
        {:other, nil}
    end
  end

  @doc false
  def unsubscribe_link_clicks_query(edition_id \\ nil)

  def unsubscribe_link_clicks_query(nil) do
    unsubscribe_link_clicks_query(Ysc.Ci.QueryExplain.Fixtures.ulid())
  end

  def unsubscribe_link_clicks_query(edition_id) when is_binary(edition_id) do
    unsubscribe_pattern = unsubscribe_link_like_pattern()

    from(e in EmailEvent,
      where: e.edition_id == ^edition_id,
      where: e.event_type == "click",
      where: not is_nil(e.link_url),
      where: like(e.link_url, ^unsubscribe_pattern),
      select: count(e.email, :distinct)
    )
  end

  @doc false
  def confirmed_unsubscribes_query(edition_id \\ nil)

  def confirmed_unsubscribes_query(nil) do
    confirmed_unsubscribes_query(Ysc.Ci.QueryExplain.Fixtures.ulid())
  end

  def confirmed_unsubscribes_query(edition_id) when is_binary(edition_id) do
    from(e in UnsubscribeEvent,
      where: e.edition_id == ^edition_id,
      select: count(e.id)
    )
  end

  @doc false
  def ci_query_explain_query, do: recent_sent_editions_query()

  @doc false
  def ci_query_explain_notices_query, do: list_notices_query()

  @doc false
  def ci_query_explain_unsubscribe_link_clicks_query,
    do: unsubscribe_link_clicks_query()

  @doc false
  def ci_query_explain_confirmed_unsubscribes_query,
    do: confirmed_unsubscribes_query()
end
