defmodule Ysc.Ci.QueryExplain.Fixtures do
  @moduledoc false

  @doc false
  def ulid, do: Ecto.ULID.generate()

  @doc false
  def uuid, do: Ecto.UUID.generate()

  @doc false
  def email, do: "ci-query-explain@example.com"

  @doc false
  def ip, do: "127.0.0.1"

  @doc false
  def token, do: :crypto.strong_rand_bytes(32)

  @doc false
  def user, do: %Ysc.Accounts.User{id: ulid()}

  @doc false
  def now, do: DateTime.utc_now()

  @doc false
  def today, do: Date.utc_today()
end
