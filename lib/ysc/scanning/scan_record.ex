defmodule Ysc.Scanning.ScanRecord do
  @moduledoc """
  Schema for individual QR scan records.

  Every successful scan creates an immutable record. Records are never deleted
  and serve as the audit trail for membership verifications and event check-ins.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "scan_records" do
    belongs_to :scan_session, Ysc.Scanning.ScanSession,
      foreign_key: :scan_session_id,
      references: :id

    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    belongs_to :ticket, Ysc.Events.Ticket,
      foreign_key: :ticket_id,
      references: :id

    belongs_to :ticket_order, Ysc.Tickets.TicketOrder,
      foreign_key: :ticket_order_id,
      references: :id

    field :checkin_type, CheckinType
    field :result, ScanResultType
    field :membership_status, :string
    field :membership_type, :string
    field :metadata, :map, default: %{}

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:scan_session_id, :checkin_type, :result, :metadata])
    |> validate_required([:scan_session_id, :result])
    |> foreign_key_constraint(:scan_session_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:ticket_id)
    |> foreign_key_constraint(:ticket_order_id)
  end
end
