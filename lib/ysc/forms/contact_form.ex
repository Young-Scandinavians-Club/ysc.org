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

  @department_cc_emails %{
    "Choir" => "choir@ysc.org",
    "Tahoe Cabin" => "tahoe@ysc.org",
    "Clear Lake Cabin" => "cl@ysc.org",
    "Membership" => "memberships@ysc.org",
    "Events" => "events@ysc.org",
    "Website" => "webtech@ysc.org",
    "Board of Directors" => "board@ysc.org"
  }

  @doc """
  Returns the department address to CC on board notifications for a contact
  subject line, or `nil` when there is no routed address.
  """
  def department_cc_for_subject(subject) when is_binary(subject) do
    Map.get(@department_cc_emails, subject)
  end

  @doc false
  def changeset(contact_form, attrs) do
    contact_form
    |> cast(attrs, [
      :name,
      :email,
      :subject,
      :message
    ])
    |> validate_required([:name, :email, :subject, :message])
    |> validate_format(:email, ~r/@/)
    |> validate_length(:message, min: 10)
  end

  @doc """
  Applies the submitting user's id after public params are validated.

  `user_id` is never taken from client params.
  """
  def put_submitter(changeset, %User{id: user_id}) do
    put_change(changeset, :user_id, user_id)
  end

  def put_submitter(changeset, _), do: changeset
end
