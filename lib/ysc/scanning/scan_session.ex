defmodule Ysc.Scanning.ScanSession do
  @moduledoc """
  Schema for QR scan sessions.

  A scan session represents a period during which an admin scans QR codes
  in either membership verification or event check-in mode.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "scan_sessions" do
    field :name, :string
    field :type, ScanSessionType

    belongs_to :event, Ysc.Events.Event, foreign_key: :event_id, references: :id

    belongs_to :created_by, Ysc.Accounts.User,
      foreign_key: :created_by_id,
      references: :id

    field :closed_at, :utc_datetime

    has_many :scan_records, Ysc.Scanning.ScanRecord

    timestamps()
  end

  @doc """
  Changeset for user-provided session attributes (:name, :type, :event_id).

  :created_by_id must be set programmatically by the context via put_change/2
  after calling this changeset, to prevent callers from spoofing ownership.
  :closed_at is managed exclusively through close_changeset/1.
  """
  def changeset(session, attrs) do
    session
    |> cast(attrs, [:name, :type, :event_id])
    |> validate_required([:name, :type])
    |> validate_inclusion(:type, [:membership, :event])
    |> validate_event_id_for_type()
    |> foreign_key_constraint(:event_id)
    |> foreign_key_constraint(:created_by_id)
  end

  def close_changeset(session) do
    change(session, closed_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp validate_event_id_for_type(changeset) do
    type = get_field(changeset, :type)
    event_id = get_field(changeset, :event_id)

    cond do
      type == :event && is_nil(event_id) ->
        add_error(changeset, :event_id, "is required for event scan sessions")

      type != :event && not is_nil(event_id) ->
        add_error(
          changeset,
          :event_id,
          "must be blank for membership scan sessions"
        )

      true ->
        changeset
    end
  end
end
