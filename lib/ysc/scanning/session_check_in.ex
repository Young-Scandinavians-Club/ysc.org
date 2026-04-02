defmodule Ysc.Scanning.SessionCheckIn do
  @moduledoc """
  Schema for membership check-ins within a scan session.

  Tracks which users were checked in during an event_membership scan session,
  along with their membership status at the time of check-in.
  Each user can only be checked in once per session (unique constraint on
  scan_session_id + user_id).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]

  schema "session_check_ins" do
    belongs_to :scan_session, Ysc.Scanning.ScanSession,
      foreign_key: :scan_session_id,
      references: :id

    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    belongs_to :checked_in_by, Ysc.Accounts.User,
      foreign_key: :checked_in_by_id,
      references: :id

    field :membership_status, :string
    field :membership_type, :string

    timestamps()
  end

  @doc """
  Changeset for user-provided attributes. The :scan_session_id, :user_id, and
  :checked_in_by_id must be set programmatically via put_change/2 BEFORE
  calling this changeset (or after, then call validate_required separately).
  """
  def changeset(check_in, attrs) do
    check_in
    |> cast(attrs, [:membership_status, :membership_type])
    |> unique_constraint([:scan_session_id, :user_id],
      name: :session_check_ins_scan_session_id_user_id_index,
      message: "User is already checked in to this session"
    )
    |> foreign_key_constraint(:scan_session_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:checked_in_by_id)
  end

  @doc """
  Validates that the required foreign keys are present. Should be called after
  the context puts :scan_session_id, :user_id, and :checked_in_by_id via
  put_change/2.
  """
  def validate_required_keys(changeset) do
    validate_required(changeset, [:scan_session_id, :user_id, :checked_in_by_id])
  end
end
