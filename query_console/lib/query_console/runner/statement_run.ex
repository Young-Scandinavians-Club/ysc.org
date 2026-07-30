defmodule QueryConsole.Runner.StatementRun do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID

  @statuses ~w(pending running completed failed cancelled)

  schema "statement_runs" do
    field :index, :integer
    field :status, :string, default: "pending"
    field :elapsed_ms, :integer
    field :row_count, :integer
    field :error_summary, :string

    belongs_to :query_run, QueryConsole.Runner.QueryRun

    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:index, :status, :elapsed_ms, :row_count, :error_summary, :query_run_id])
    |> validate_required([:index, :status, :query_run_id])
    |> validate_inclusion(:status, @statuses)
  end
end
