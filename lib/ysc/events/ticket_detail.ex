defmodule Ysc.Events.TicketDetail do
  @moduledoc """
  Ticket detail schema and changesets.

  Defines the TicketDetail database schema, validations, and changeset functions
  for ticket detail data manipulation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "ticket_details" do
    belongs_to :ticket, Ysc.Events.Ticket,
      foreign_key: :ticket_id,
      references: :id

    field :first_name, :string
    field :last_name, :string
    field :email, :string

    timestamps()
  end

  @doc """
  Creates a changeset for the TicketDetail schema.
  """
  def changeset(ticket_detail, attrs \\ %{}) do
    ticket_detail
    |> cast(attrs, [:ticket_id, :first_name, :last_name, :email])
    |> validate_required([:ticket_id, :first_name, :last_name, :email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "must be a valid email address"
    )
    |> foreign_key_constraint(:ticket_id)
  end
end
