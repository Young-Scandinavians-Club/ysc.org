defmodule Ysc.Csv do
  @moduledoc """
  Helpers for CSV exports that admins and volunteers open in a spreadsheet.

  Spreadsheet apps treat a cell starting with `=`, `+`, `-`, `@`, tab, or
  carriage return as a formula. Prefix those values with an apostrophe so
  they stay data. Plain negative integers (`-42`) are left alone.
  """

  @formula_prefixes ["=", "+", "-", "@", "\t", "\r"]

  @doc """
  Returns `value` unchanged unless it is a formula-like string.
  """
  def sanitize_cell(value) when is_binary(value) do
    cond do
      Regex.match?(~r/^-\d+$/, value) ->
        value

      String.starts_with?(value, @formula_prefixes) ->
        "'" <> value

      true ->
        value
    end
  end

  def sanitize_cell(value), do: value

  @doc """
  Sanitizes every cell in a list row, or every key and value in a map row.
  """
  def sanitize_row(row) when is_list(row), do: Enum.map(row, &sanitize_cell/1)

  def sanitize_row(row) when is_map(row) do
    Map.new(row, fn {k, v} -> {sanitize_cell(k), sanitize_cell(v)} end)
  end
end
