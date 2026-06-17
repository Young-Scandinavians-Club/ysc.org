defmodule Ysc.WpMigration.BackupMetaParser do
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
