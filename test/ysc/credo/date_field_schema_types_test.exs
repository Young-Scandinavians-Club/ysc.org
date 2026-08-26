defmodule Ysc.Credo.DateFieldSchemaTypesTest do
  use ExUnit.Case, async: true

  alias Ysc.Credo.DateFieldSchemaTypes

  setup_all do
    {:ok, _} = Application.ensure_all_started(:credo)
    :ok
  end

  defp issues_for(source) do
    source
    |> Credo.SourceFile.parse("lib/ysc/events/sample.ex")
    |> DateFieldSchemaTypes.run([])
  end

  test "flags a bare :utc_datetime start_date" do
    issues =
      issues_for("""
      defmodule Ysc.Events.Sample do
        use Ecto.Schema

        schema "samples" do
          field :start_date, :utc_datetime
        end
      end
      """)

    assert [%Credo.Issue{check: DateFieldSchemaTypes}] = issues
    assert hd(issues).message =~ "Ysc.Ecto.DateKind"
  end

  test "accepts a DateKind field" do
    issues =
      issues_for("""
      defmodule Ysc.Events.Sample do
        use Ecto.Schema

        schema "samples" do
          field :start_date, Ysc.Ecto.DateKind, kind: :california_calendar_datetime
          field :title, :string
        end
      end
      """)

    assert issues == []
  end

  test "flags an unknown kind" do
    issues =
      issues_for("""
      defmodule Ysc.Events.Sample do
        use Ecto.Schema

        schema "samples" do
          field :start_date, Ysc.Ecto.DateKind, kind: :not_a_kind
        end
      end
      """)

    assert [%Credo.Issue{}] = issues
    assert hd(issues).message =~ "Unknown"
  end
end
