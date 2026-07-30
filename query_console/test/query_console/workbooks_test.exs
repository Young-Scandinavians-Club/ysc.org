defmodule QueryConsole.WorkbooksTest do
  use QueryConsole.DataCase, async: true

  alias QueryConsole.Workbooks

  test "owner can CRUD workbooks; other users cannot access" do
    owner = user_fixture()
    other = user_fixture()

    assert {:ok, workbook} = Workbooks.create_workbook(owner, %{title: "Mine", sql: "SELECT 1"})
    assert {:ok, ^workbook} = Workbooks.get_workbook(owner, workbook.id)
    assert {:error, :forbidden} = Workbooks.get_workbook(other, workbook.id)

    assert {:ok, updated} = Workbooks.update_workbook(owner, workbook, %{title: "Updated"})
    assert updated.title == "Updated"
    assert {:error, :forbidden} = Workbooks.update_workbook(other, workbook, %{title: "Hack"})

    assert {:ok, _} = Workbooks.autosave(owner, workbook, "SELECT 2")
    assert {:error, :forbidden} = Workbooks.autosave(other, workbook, "SELECT 3")

    assert {:ok, revisions} = Workbooks.list_revisions(owner, workbook.id)
    assert length(revisions) >= 1

    assert {:error, :forbidden} = Workbooks.delete_workbook(other, workbook.id)
    assert {:ok, _} = Workbooks.delete_workbook(owner, workbook.id)
  end

  test "autosave keeps only last N revisions" do
    owner = user_fixture()
    workbook = workbook_fixture(owner)

    for i <- 1..55 do
      assert {:ok, _} = Workbooks.autosave(owner, workbook, "SELECT #{i}")
    end

    assert {:ok, revisions} = Workbooks.list_revisions(owner, workbook.id)
    assert length(revisions) == 50
  end
end
