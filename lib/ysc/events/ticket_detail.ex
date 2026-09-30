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

    # Answers to the ticket tier's `attendee_questions`, keyed by question id:
    # `%{"<id>" => %{"label" => ..., "type" => ..., "position" => ..., "value" => ...}}`.
    # See `Ysc.Events.AttendeeInfo`.
    field :answers, :map, default: %{}

    timestamps()
  end

  @doc """
  Creates a changeset for the TicketDetail schema.

  By default the attendee's first name, last name and email are required.
  Pass `identity: false` for tickets whose tier only asks extra questions and
  doesn't collect who is attending; the name/email fields are then optional
  (though still format-checked when given). Pass `require_email: false` to
  require a name but not an email, for tickets that only need a name.
  """
  def changeset(ticket_detail, attrs \\ %{}, opts \\ []) do
    identity? = Keyword.get(opts, :identity, true)
    email? = Keyword.get(opts, :require_email, true)

    required =
      cond do
        not identity? -> [:ticket_id]
        email? -> [:ticket_id, :first_name, :last_name, :email]
        true -> [:ticket_id, :first_name, :last_name]
      end

    ticket_detail
    |> cast(attrs, [:ticket_id, :first_name, :last_name, :email, :answers])
    |> validate_required(required)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "must be a valid email address"
    )
    |> foreign_key_constraint(:ticket_id)
  end
end
