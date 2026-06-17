defmodule Ysc.WpMigration.FamilyMembersBackupIntegrationTest do
  @moduledoc """
  Validates family member parsing against the real WordPress SQL backup when present.

  Tagged `:backup_integration` so it can be skipped in CI without the backup file:
      mix test --exclude backup_integration
  """

  use ExUnit.Case, async: false

  alias Ysc.WpMigration.FamilyMembers
  alias Ysc.WpMigration.FamilyMembersFixtures
  alias Ysc.WpMigration.FamilyMembersBackupIntegrationTest.BackupMetaParser

  @backup Path.expand("backup/YoungScandinaviansClub-061526-backup/backup.sql")
  @tag :backup_integration
  @tag timeout: 180_000
  test "backup users with spouse/child usermeta all produce importable family records" do
    with_backup_file(fn ->
      users = BackupMetaParser.collect_family_users(@backup)

      assert length(users) >= 900,
             "expected at least 900 WP users with family usermeta, got #{length(users)}"

      failures =
        Enum.reduce(users, [], fn {wp_user_id, meta}, acc ->
          row =
            FamilyMembersFixtures.application_row_from_meta(wp_user_id, meta)

          records = FamilyMembers.build_records(row)

          cond do
            records == [] ->
              [{wp_user_id, "no records built", meta} | acc]

            invalid_record?(records) ->
              [{wp_user_id, "invalid record attrs", records} | acc]

            true ->
              acc
          end
        end)

      assert failures == [],
             "failed to build family records for #{length(failures)} users: #{inspect(Enum.take(failures, 5))}"
    end)
  end

  @tag :backup_integration
  @tag timeout: 180_000
  test "extract application_from_usermeta matches fixture builder for backup users" do
    with_backup_file(fn ->
      users =
        @backup
        |> BackupMetaParser.collect_family_users()
        |> Enum.take(50)

      for {wp_user_id, meta} <- users do
        fixture_row =
          FamilyMembersFixtures.application_row_from_meta(wp_user_id, meta)

        extracted =
          Ysc.WpMigration.Extract.application_from_usermeta(
            wp_user_id,
            "user-#{wp_user_id}@example.com",
            "2018-01-01T00:00:00",
            meta
          )

        assert normalize_row_children(fixture_row) ==
                 normalize_row_children(extracted),
               "children mismatch for WP user #{wp_user_id}"

        assert fixture_row["spouse_first_name"] ==
                 extracted["spouse_first_name"]

        assert fixture_row["spouse_last_name"] == extracted["spouse_last_name"]
      end
    end)
  end

  defp with_backup_file(fun) when is_function(fun, 0) do
    if File.exists?(@backup) do
      fun.()
    else
      IO.puts("Skipping: backup.sql not found at #{@backup}")
      assert true
    end
  end

  defp invalid_record?(records) do
    Enum.any?(records, fn r ->
      r.first_name in [nil, ""] or r.last_name in [nil, ""] or
        r.type not in [:spouse, :child]
    end)
  end

  defp normalize_row_children(row) do
    row
    |> Map.get("children", [])
    |> Enum.map(fn c -> {c["name"], c["birthday"]} end)
  end
end

defmodule Ysc.WpMigration.FamilyMembersBackupIntegrationTest.BackupMetaParser do
  @moduledoc false

  @meta_keys MapSet.new([
               "spouse_first_name",
               "spouse_last_name",
               "first_child_name",
               "second_child_name",
               "third_child_name",
               "fourth_child_name",
               "first_child_birthday",
               "second_child_birthday",
               "third_child_birthday",
               "fourth_child_birthday",
               "membership_type"
             ])

  @tuple_re ~r/\(\d+,(\d+),'([^']+)','((?:\\.|[^'\\])*)'/

  def collect_family_users(path) do
    path
    |> File.stream!(16_384_000, [])
    |> Stream.flat_map(&parse_line/1)
    |> Enum.reduce(%{}, fn {user_id, key, value}, acc ->
      if MapSet.member?(@meta_keys, key) and value != "" do
        Map.update(acc, user_id, %{key => value}, &Map.put(&1, key, value))
      else
        acc
      end
    end)
    |> Enum.filter(fn {_id, meta} -> family_meta?(meta) end)
    |> Enum.sort_by(fn {id, _} -> String.to_integer(id) end)
  end

  defp family_meta?(meta) do
    Enum.any?(meta, fn {k, _} ->
      String.starts_with?(k, "spouse_") or String.ends_with?(k, "_child_name")
    end)
  end

  defp parse_line(line) do
    if String.contains?(line, "wp0h_usermeta") and
         String.contains?(line, "INSERT") do
      line
      |> then(&Regex.scan(@tuple_re, &1, capture: :all_but_first))
      |> Enum.flat_map(fn
        [user_id, key, value] when is_binary(key) ->
          if MapSet.member?(@meta_keys, key) do
            [{user_id, key, unescape(value)}]
          else
            []
          end

        _ ->
          []
      end)
    else
      []
    end
  end

  defp unescape(value) do
    value
    |> String.replace(~S(\'), "'")
    |> String.replace(~S(\\\\), "\\")
  end
end
