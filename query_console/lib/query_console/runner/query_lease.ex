defmodule QueryConsole.Runner.QueryLease do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID

  schema "query_leases" do
    field :holder, :string
    field :acquired_at, :utc_datetime
    field :expires_at, :utc_datetime

    belongs_to :query_run, QueryConsole.Runner.QueryRun
  end

  def changeset(lease, attrs) do
    lease
    |> cast(attrs, [:holder, :query_run_id, :acquired_at, :expires_at])
    |> validate_required([:holder, :acquired_at, :expires_at])
    |> unique_constraint(:holder)
  end
end
