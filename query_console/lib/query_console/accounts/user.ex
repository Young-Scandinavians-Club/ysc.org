defmodule QueryConsole.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID

  schema "users" do
    field :ysc_user_id, :string
    field :email, :string
    field :display_name, :string
    field :role, :string, default: "admin"
    field :last_login_at, :utc_datetime

    has_many :workbooks, QueryConsole.Workbooks.Workbook

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:ysc_user_id, :email, :display_name, :role, :last_login_at])
    |> validate_required([:ysc_user_id, :email, :role])
    |> unique_constraint(:ysc_user_id)
  end
end
