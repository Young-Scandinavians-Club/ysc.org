defmodule QueryConsole.Repo.Migrations.UpgradeLotusTablesToV6 do
  use Ecto.Migration

  # Lotus 1.x adds migrations V4 (data_repo -> data_source), V5 (query_language),
  # and V6 (dashboard filter source queries). Fresh databases already reach V6 in
  # CreateLotusTables; existing ones were at V3 (Lotus 0.16.x).
  def up, do: Lotus.Migrations.up()
  def down, do: Lotus.Migrations.down(version: 4)
end
