defmodule QueryConsole.Runner.QueryRun do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID

  @statuses ~w(queued validating acquiring_connection running completed failed timed_out cancelled)
  @modes ~w(selection current all)

  schema "query_runs" do
    field :status, :string, default: "queued"
    field :mode, :string, default: "all"
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :error_summary, :string
    field :statement_count, :integer, default: 0

    belongs_to :user, QueryConsole.Accounts.User
    belongs_to :workbook, QueryConsole.Workbooks.Workbook
    has_many :statement_runs, QueryConsole.Runner.StatementRun

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def modes, do: @modes

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :status,
      :mode,
      :started_at,
      :finished_at,
      :error_summary,
      :statement_count,
      :user_id,
      :workbook_id
    ])
    |> validate_required([:status, :mode])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:mode, @modes)
  end
end
