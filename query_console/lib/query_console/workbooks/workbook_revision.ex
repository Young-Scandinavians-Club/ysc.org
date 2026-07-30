defmodule QueryConsole.Workbooks.WorkbookRevision do
  use Ecto.Schema

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID

  schema "workbook_revisions" do
    field :sql, :string
    field :inserted_at, :utc_datetime

    belongs_to :workbook, QueryConsole.Workbooks.Workbook
  end
end
