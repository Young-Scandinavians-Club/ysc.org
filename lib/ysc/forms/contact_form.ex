defmodule Ysc.Forms.ContactForm do
  @moduledoc """
  Contact form schema and changesets.

  Defines the ContactForm database schema, validations, and changeset functions
  for contact form submissions.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ysc.Accounts.User

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "contact_forms" do
    field :name, :string
    field :email, :string
    field :subject, :string
    field :message, :string

    belongs_to :user, User, foreign_key: :user_id, references: :id

    timestamps()
  end

  @doc false
  def changeset(contact_form, attrs) do
    contact_form
    |> cast(attrs, [
      :name,
      :email,
      :subject,
      :message,
      :user_id
    ])
    |> validate_required([:name, :email, :subject, :message])
    |> validate_format(:email, ~r/@/)
    |> validate_length(:message, min: 10)
  end
end
