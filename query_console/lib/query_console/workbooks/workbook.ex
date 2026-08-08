defmodule QueryConsole.Workbooks.Workbook do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID

  schema "workbooks" do
    field :title, :string, default: "Untitled"
    field :sql, :string, default: ""

    belongs_to :user, QueryConsole.Accounts.User
    has_many :revisions, QueryConsole.Workbooks.WorkbookRevision

    timestamps(type: :utc_datetime)
  end

  def changeset(workbook, attrs) do
    workbook
    |> cast(attrs, [:title, :sql])
    |> validate_required([:title])
    |> validate_length(:title, max: 200)
    |> maybe_default_sql()
  end

  defp maybe_default_sql(changeset) do
    case get_field(changeset, :sql) do
      nil -> put_change(changeset, :sql, "")
      _ -> changeset
    end
  end
end
