defmodule QueryConsole.Catalog.SchemaSnapshot do
  use Ecto.Schema

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID

  schema "schema_snapshots" do
    field :version, :integer
    field :payload, :map
    field :inserted_at, :utc_datetime
  end
end
