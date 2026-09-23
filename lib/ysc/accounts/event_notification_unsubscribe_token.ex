defmodule Ysc.Accounts.EventNotificationUnsubscribeToken do
  @moduledoc """
  Signed, non-expiring tokens that let a user unsubscribe from event
  notification emails (event announcements and Tahoe weekend availability
  alerts) without signing in, mirroring the newsletter unsubscribe-by-token
  flow.

  The token carries no state of its own — it just proves the holder was sent
  this user's link — so unsubscribing is idempotent and safe to retry.
  """

  @salt "event_notifications_unsubscribe_v1"

  @doc """
  Signs an unsubscribe token for `user_id`.
  """
  def sign(user_id) when is_binary(user_id) do
    Phoenix.Token.sign(YscWeb.Endpoint, @salt, user_id, max_age: :infinity)
  end

  @doc """
  Verifies `token`, returning `{:ok, user_id}` or `{:error, :invalid}`.
  """
  def verify(token) when is_binary(token) and byte_size(token) > 0 do
    case Phoenix.Token.verify(YscWeb.Endpoint, @salt, token, max_age: :infinity) do
      {:ok, user_id} -> {:ok, user_id}
      {:error, _} -> {:error, :invalid}
    end
  end

  def verify(_), do: {:error, :invalid}
end
