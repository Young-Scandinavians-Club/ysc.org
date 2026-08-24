defmodule Ysc.Text do
  @moduledoc """
  Shared text formatting helpers used by LiveViews, controllers, and domain code.
  """

  @doc """
  Title-cases an atom or underscored identifier (`:clear_lake` → `"Clear Lake"`).

  Returns `fallback` (default `"—"`) for `nil` and other non-string/non-atom values.

  ## Examples

      iex> Ysc.Text.titleize(:clear_lake)
      "Clear Lake"

      iex> Ysc.Text.titleize("vice_president")
      "Vice President"

      iex> Ysc.Text.titleize(nil)
      "—"
  """
  def titleize(value, fallback \\ "—")

  def titleize(value, _fallback) when is_binary(value) do
    value
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  def titleize(nil, fallback), do: fallback

  def titleize(value, fallback) when is_atom(value) do
    value
    |> Atom.to_string()
    |> titleize(fallback)
  end

  def titleize(_, fallback), do: fallback
end
