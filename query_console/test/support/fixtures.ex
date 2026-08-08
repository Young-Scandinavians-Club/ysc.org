defmodule QueryConsole.Fixtures do
  @moduledoc """
  Test fixtures for users and workbooks.
  """

  alias QueryConsole.Accounts
  alias QueryConsole.Workbooks

  def user_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    claims =
      Map.merge(
        %{
          "ysc_user_id" => "ysc-user-#{unique}",
          "email" => "user#{unique}@example.com",
          "display_name" => "User #{unique}",
          "role" => "admin"
        },
        stringify(attrs)
      )

    {:ok, user} = Accounts.upsert_from_sso(claims)
    user
  end

  def workbook_fixture(user, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{"title" => "Workbook #{System.unique_integer([:positive])}", "sql" => "SELECT 1"},
        stringify(attrs)
      )

    {:ok, workbook} = Workbooks.create_workbook(user, attrs)
    workbook
  end

  defp stringify(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
