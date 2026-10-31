defmodule Ysc.Merch.CartEvents do
  @moduledoc """
  Records `Ysc.Merch.CartEvent` rows for cart changes.

  The log is for analytics only, so a failure to write it is logged and
  swallowed rather than breaking the member's cart.
  """
  import Ecto.Query, warn: false

  require Ysc.Logging

  alias Ysc.Merch.CartEvent
  alias Ysc.Repo

  @doc """
  Records one event per `{variant_id, action, quantity}` entry for the member.
  """
  @spec record(String.t(), [{String.t(), atom(), integer()}]) :: :ok
  def record(_user_id, []), do: :ok

  def record(user_id, entries) when is_binary(user_id) and is_list(entries) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(entries, fn {variant_id, action, quantity} ->
        %{
          id: Ecto.ULID.generate(),
          user_id: user_id,
          variant_id: variant_id,
          action: action,
          quantity: quantity,
          inserted_at: now
        }
      end)

    Repo.insert_all(CartEvent, rows)
    :ok
  rescue
    error ->
      Ysc.Logging.warning("Could not record merch cart event",
        error: error,
        extra: %{user_id: user_id, entries: length(entries)}
      )

      :ok
  end

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    from(e in CartEvent,
      where: e.user_id == ^Fixtures.ulid() and e.action == :added,
      order_by: [desc: e.inserted_at],
      limit: 50
    )
  end
end
