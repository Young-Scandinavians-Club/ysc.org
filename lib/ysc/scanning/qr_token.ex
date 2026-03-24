defmodule Ysc.Scanning.QrToken do
  @moduledoc """
  Generates and verifies signed QR tokens for membership and ticket scanning.

  Neither token type expires — membership validity is checked in real-time against
  the database at scan time, and ticket validity is enforced by ticket status,
  event match, and checked_in flag.
  """

  @membership_salt "membership_qr_v1"
  @ticket_salt "ticket_qr_v1"

  @doc """
  Signs a membership QR token for the given user ID.
  Token does not expire; membership status is validated server-side at scan time.
  """
  def sign_membership(user_id) do
    Phoenix.Token.sign(
      YscWeb.Endpoint,
      @membership_salt,
      {:membership, user_id}
    )
  end

  @doc """
  Signs a ticket QR token for the given ticket ID.
  Token does not expire; validity is checked server-side against the ticket's DB state.
  """
  def sign_ticket(ticket_id) do
    Phoenix.Token.sign(YscWeb.Endpoint, @ticket_salt, {:ticket, ticket_id})
  end

  @doc """
  Verifies a QR token and returns its payload.

  Returns:
  - `{:ok, {:membership, user_id}}` for valid membership tokens
  - `{:ok, {:ticket, ticket_id}}` for valid ticket tokens
  - `{:error, :invalid}` if the token is not valid
  """
  def verify(token) when is_binary(token) do
    case Phoenix.Token.verify(YscWeb.Endpoint, @membership_salt, token) do
      {:ok, {:membership, _user_id} = payload} ->
        {:ok, payload}

      {:error, _} ->
        case Phoenix.Token.verify(YscWeb.Endpoint, @ticket_salt, token) do
          {:ok, {:ticket, _ticket_id} = payload} -> {:ok, payload}
          {:error, _} -> {:error, :invalid}
        end
    end
  end

  def verify(_), do: {:error, :invalid}
end
