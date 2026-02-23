defmodule Ysc.Accounts.BoardPosition do
  @moduledoc """
  Board position history schema.

  Tracks when a user held a board position. A record with `ended_on: nil`
  represents the current position (also reflected on `users.board_position`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "board_positions" do
    belongs_to :user, Ysc.Accounts.User
    field :position, BoardMemberPosition
    field :started_on, :date
    field :ended_on, :date

    timestamps()
  end

  def changeset(board_position, attrs) do
    board_position
    |> cast(attrs, [:user_id, :position, :started_on, :ended_on])
    |> validate_required([:user_id, :position, :started_on])
    |> foreign_key_constraint(:user_id)
  end
end
