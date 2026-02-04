defmodule Ysc.Webhooks.DuplicateWebhookEventError do
  defexception message: "Webhook event already exists"
end

defmodule Ysc.Webhooks do
  @moduledoc """
  Context module for managing webhook events.

  Handles creation, retrieval, and processing of webhook events from external services.
  """
  alias Ysc.Webhooks.WebhookEvent
  alias Ysc.Repo
  import Ecto.Query

  @doc """
  Creates a webhook event, raising an error if a duplicate event exists.
  The error can be caught and handled by the caller.
  """
  def create_webhook_event!(attrs) do
    %WebhookEvent{}
    |> WebhookEvent.changeset(attrs)
    |> Repo.insert!()
  rescue
    _error ->
      exception = %Ysc.Webhooks.DuplicateWebhookEventError{
        message: "Webhook event already exists"
      }

      reraise exception, __STACKTRACE__
  end

  @doc """
  Locks a webhook event for processing. Returns {:ok, webhook_event} if successful,
  {:error, :not_found} if the event doesn't exist, or {:error, :already_processing}
  if the event is already being processed.
  """
  def lock_webhook_event(event_id) do
    # Use FOR UPDATE SKIP LOCKED to handle concurrent processing attempts
    query =
      from(w in WebhookEvent,
        where: w.id == ^event_id and w.state == :pending,
        lock: "FOR UPDATE SKIP LOCKED"
      )

    case Repo.one(query) do
      nil ->
        case Repo.get(WebhookEvent, event_id) do
          nil ->
            {:error, :not_found}

          %WebhookEvent{state: state} when state != :pending ->
            {:error, :already_processing}
        end

      webhook_event ->
        {:ok, _updated} =
          webhook_event
          |> Ecto.Changeset.change(%{state: :processing})
          |> Repo.update()

        {:ok, webhook_event}
    end
  end

  @doc """
  Gets and locks a webhook event by ID until processed.
  Returns {:ok, webhook_event} if found and locked, {:error, :not_found} otherwise.
  """
  def get_and_lock_webhook(id) do
    query =
      from(w in WebhookEvent,
        where: w.id == ^id,
        lock: "FOR UPDATE SKIP LOCKED"
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      webhook -> {:ok, webhook}
    end
  end

  @doc """
  Updates the state of a webhook event.
  Returns {:ok, webhook_event} if successful, {:error, changeset} if validation fails.
  """
  def update_webhook_state(webhook, state) do
    webhook
    |> Ecto.Changeset.change(%{state: state})
    |> Repo.update()
  end

  @doc """
  Lists all unprocessed webhook event IDs (those in pending state).
  Returns a list of webhook event IDs.
  """
  def list_unprocessed_webhook_ids do
    WebhookEvent
    |> where([w], w.state == :pending)
    |> select([w], w.id)
    |> Repo.all()
  end

  @doc """
  Updates a webhook event's state to complete or failed.
  Returns {:ok, webhook_event} if successful, or {:error, :not_found} if not found.
  """
  def update_webhook_event_state(event_id, new_state)
      when new_state in [:processed, :failed] do
    case Repo.get(WebhookEvent, event_id) do
      nil ->
        {:error, :not_found}

      webhook_event ->
        webhook_event
        |> Ecto.Changeset.change(%{state: new_state})
        |> Repo.update()
    end
  end

  @doc """
  Lists pending webhook events.
  Optional limit parameter to control the number of events returned.
  """
  def list_pending_webhook_events(limit \\ 100) do
    WebhookEvent
    |> where([w], w.state == :pending)
    |> order_by([w], asc: w.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets a webhook event by ID.
  Returns nil if not found.
  """
  def get_webhook_event(event_id) do
    Repo.get(WebhookEvent, event_id)
  end

  @doc """
  Gets a webhook event by provider and event_id.
  Returns nil if not found.
  """
  def get_webhook_event_by_provider_and_event_id(provider, event_id) do
    Repo.get_by(WebhookEvent, provider: provider, event_id: event_id)
  end

  @doc """
  Locks a webhook event by provider and event_id for processing.
  Returns {:ok, webhook_event} if successful, {:error, :not_found} if not found,
  or {:error, :already_processing} if already being processed.
  """
  def lock_webhook_event_by_provider_and_event_id(provider, event_id) do
    # Use FOR UPDATE SKIP LOCKED to handle concurrent processing attempts
    query =
      from(w in WebhookEvent,
        where:
          w.provider == ^provider and w.event_id == ^event_id and
            w.state == :pending,
        lock: "FOR UPDATE SKIP LOCKED"
      )

    case Repo.one(query) do
      nil ->
        case get_webhook_event_by_provider_and_event_id(provider, event_id) do
          nil ->
            {:error, :not_found}

          %WebhookEvent{state: state} when state != :pending ->
            {:error, :already_processing}
        end

      webhook_event ->
        {:ok, _updated} =
          webhook_event
          |> Ecto.Changeset.change(%{state: :processing})
          |> Repo.update()

        {:ok, webhook_event}
    end
  end

  @doc """
  Lists webhook events with optional filters.

  Options:
  - `:provider` - Filter by provider (e.g., "stripe")
  - `:state` - Filter by state (e.g., :processed, :failed, :pending, :processing)
  - `:start_date` - Filter events inserted after this DateTime
  - `:end_date` - Filter events inserted before this DateTime
  - `:limit` - Maximum number of events to return (default: 100)
  - `:order_by` - Order by :inserted_at (default: :desc)
  """
  def list_webhook_events(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    order_by = Keyword.get(opts, :order_by, :desc)

    query =
      WebhookEvent
      |> maybe_filter_by_provider(Keyword.get(opts, :provider))
      |> maybe_filter_by_state(Keyword.get(opts, :state))
      |> maybe_filter_by_date_range(
        Keyword.get(opts, :start_date),
        Keyword.get(opts, :end_date)
      )
      |> order_by([w], [{^order_by, w.inserted_at}])
      |> limit(^limit)

    Repo.all(query)
  end

  defp maybe_filter_by_provider(query, nil), do: query

  defp maybe_filter_by_provider(query, provider) do
    where(query, [w], w.provider == ^provider)
  end

  defp maybe_filter_by_state(query, nil), do: query

  defp maybe_filter_by_state(query, state) do
    where(query, [w], w.state == ^state)
  end

  defp maybe_filter_by_date_range(query, nil, nil), do: query

  defp maybe_filter_by_date_range(query, start_date, nil) do
    where(query, [w], w.inserted_at >= ^start_date)
  end

  defp maybe_filter_by_date_range(query, nil, end_date) do
    where(query, [w], w.inserted_at <= ^end_date)
  end

  defp maybe_filter_by_date_range(query, start_date, end_date) do
    where(
      query,
      [w],
      w.inserted_at >= ^start_date and w.inserted_at <= ^end_date
    )
  end
end
