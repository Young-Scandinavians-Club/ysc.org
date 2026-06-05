defmodule Ysc.Ci.QueryExplain.Fixtures do
  @moduledoc false

  @stable_ulid "01ARZ3NDEKTSV4RRFFQ69G5FAV"
  @stable_uuid "123e4567-e89b-12d3-a456-426614174000"
  @stable_now ~U[2024-01-01 00:00:00Z]
  @stable_today ~D[2024-01-01]

  @doc false
  def ulid, do: @stable_ulid

  @doc false
  def uuid, do: @stable_uuid

  @doc false
  def email, do: "ci-query-explain@example.com"

  @doc false
  def ip, do: "127.0.0.1"

  @doc false
  def token, do: :crypto.strong_rand_bytes(32)

  @doc false
  def user, do: %Ysc.Accounts.User{id: @stable_ulid}

  @doc false
  def now, do: @stable_now

  @doc false
  def today, do: @stable_today
end
