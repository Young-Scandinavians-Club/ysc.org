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
  alias Ysc.Newsletter.Subscriber

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

  Returns `{:ok, subscriber}` or `{:error, changeset}`.
  """
  def subscribe(email, opts \\ []) do
    if valid_email?(email) do
      do_subscribe(String.trim(email), opts)
    else
      {:error, :invalid_email}
    end
  end

  defp do_subscribe(email, opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    user_id = Keyword.get(opts, :user_id)
    first_name = Keyword.get(opts, :first_name)
    last_name = Keyword.get(opts, :last_name)
    source = Keyword.get(opts, :source, "public_signup")
    metadata = Keyword.get(opts, :metadata, %{})

    case get_subscriber_by_email(email) do
      nil ->
        create_subscriber(
          email,
          now,
          user_id,
          first_name,
          last_name,
          source,
          metadata
        )

      existing ->
        update_existing_subscriber(
          existing,
          now,
          user_id,
          first_name,
          last_name,
          source,
          metadata
        )
    end
  end

  defp create_subscriber(
         email,
         now,
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
      source: source,
      metadata: metadata,
      subscribed_at: now,
      unsubscribed_at: nil
    })
    |> Repo.insert()
  end

  defp update_existing_subscriber(
         existing,
         now,
         user_id,
         first_name,
         last_name,
         source,
         metadata
       ) do
    # If we now have a user_id but existing record doesn't, link them
    link_user = user_id && is_nil(existing.user_id)
    new_source = if link_user, do: "user_registration_linked", else: source

    attrs = %{
      subscribed: true,
      unsubscribed_at: nil,
      source: new_source,
      metadata: Map.merge(existing.metadata || %{}, metadata)
    }

    attrs =
      attrs
      |> maybe_put(:user_id, user_id || existing.user_id)
      |> maybe_put(:first_name, first_name || existing.first_name)
      |> maybe_put(:last_name, last_name || existing.last_name)

    # Preserve original subscribed_at when re-subscribing
    attrs =
      if existing.subscribed,
        do: attrs,
        else: Map.put(attrs, :subscribed_at, now)

    existing
    |> Subscriber.update_changeset(attrs)
    |> Repo.update()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc """
  Unsubscribes by email or by subscription token.

  Returns `{:ok, subscriber}` or `{:error, :not_found}`.
  """
  def unsubscribe(email_or_token) when is_binary(email_or_token) do
    cond do
      String.contains?(email_or_token, "@") ->
        unsubscribe_by_email(email_or_token)

      true ->
        unsubscribe_by_token(email_or_token)
    end
  end

  defp unsubscribe_by_email(email) do
    case get_subscriber_by_email(email) do
      nil -> {:error, :not_found}
      subscriber -> do_unsubscribe(subscriber)
    end
  end

  defp unsubscribe_by_token(token) do
    case get_subscriber_by_token(token) do
      nil -> {:error, :not_found}
      subscriber -> do_unsubscribe(subscriber)
    end
  end

  defp do_unsubscribe(subscriber) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    subscriber
    |> Subscriber.update_changeset(%{
      subscribed: false,
      unsubscribed_at: now
    })
    |> Repo.update()
  end

  @doc """
  Returns the subscriber for the given email, or nil.
  """
  def get_subscriber_by_email(email) when is_binary(email) do
    Repo.get_by(Subscriber, email: email)
  end

  @doc """
  Returns the subscriber for the given subscription token, or nil.
  """
  def get_subscriber_by_token(token) when is_binary(token) do
    Repo.get_by(Subscriber, subscription_token: token)
  end

  @doc """
  Syncs the newsletter_subscribers table with the user's newsletter_notifications preference.

  If the user has newsletter_notifications enabled, subscribes their email (or links
  existing subscription). If disabled, unsubscribes their email.
  """
  def sync_user_preference(user) do
    if user.newsletter_notifications do
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

  defp valid_email?(email) do
    is_binary(email) && String.trim(email) != "" && String.contains?(email, "@")
  end
end
