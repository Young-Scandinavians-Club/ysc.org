defmodule Ysc.WpMigration.MembershipPlanBackupTest do
  use ExUnit.Case, async: false

  alias Ysc.WpMigration.{MembershipPlan, WpRepo}

  @backup_db Path.expand(
               "../../../backup/YoungScandinaviansClub-061526-backup/wp.duckdb",
               __DIR__
             )

  @tag :backup_integration
  test "active membership product names map to family or single plans" do
    with_duckdb_backup(fn ->
      assert {:ok, repo} = WpRepo.open(@backup_db)

      assert {:ok, membership} = WpRepo.get_membership_for_user(repo, "123706")

      assert membership["wcm_product_name"] == "One Year Single Membership"

      assert MembershipPlan.resolve(%{
               wcm_product_name: membership["wcm_product_name"]
             }) ==
               "single"

      assert {:ok, family_membership} =
               WpRepo.get_membership_for_user(repo, "2293")

      assert family_membership["wcm_product_name"] ==
               "One Year Family Membership"

      assert MembershipPlan.resolve(%{
               wcm_product_name: family_membership["wcm_product_name"]
             }) == "family"
    end)
  end

  defp with_duckdb_backup(fun) when is_function(fun, 0) do
    cond do
      not Code.ensure_loaded?(Duckdbex) ->
        IO.puts("Skipping: Duckdbex is not available in this Mix env")
        assert true

      not File.exists?(@backup_db) ->
        IO.puts("Skipping: wp.duckdb not found at #{@backup_db}")
        assert true

      true ->
        fun.()
    end
  end
end
