defmodule Ysc.WpMigration.FamilyMembersFixtures do
  @moduledoc false

  @fixture_path Path.join([
                  "test",
                  "fixtures",
                  "wp_migration",
                  "family_backup_samples.json"
                ])

  def backup_samples do
    @fixture_path
    |> Path.expand()
    |> File.read!()
    |> Jason.decode!()
  end

  @doc """
  Converts raw WP usermeta (as in the SQL backup) into an `applications.json` row.
  """
  def application_row_from_meta(wp_user_id, meta) when is_map(meta) do
    children =
      Enum.flat_map(1..4, fn i ->
        name_key = child_name_key(i)
        bday_key = child_birthday_key(i)
        name = presence(meta[name_key])

        if name do
          [%{"name" => name, "birthday" => presence(meta[bday_key])}]
        else
          []
        end
      end)

    %{
      "wp_user_id" => wp_user_id,
      "email" => "wp-#{wp_user_id}@migration.test",
      "membership_type" => meta["membership_type"] || "family",
      "spouse_first_name" => presence(meta["spouse_first_name"]),
      "spouse_last_name" => presence(meta["spouse_last_name"]),
      "children" => children,
      "has_submitted_application" => true
    }
  end

  defp child_name_key(1), do: "first_child_name"
  defp child_name_key(2), do: "second_child_name"
  defp child_name_key(3), do: "third_child_name"
  defp child_name_key(4), do: "fourth_child_name"

  defp child_birthday_key(1), do: "first_child_birthday"
  defp child_birthday_key(2), do: "second_child_birthday"
  defp child_birthday_key(3), do: "third_child_birthday"
  defp child_birthday_key(4), do: "fourth_child_birthday"

  defp presence(nil), do: nil
  defp presence(""), do: nil

  defp presence(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp presence(value), do: value
end
