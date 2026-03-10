defmodule Ysc do
  @moduledoc """
  Ysc keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  Capitalizes every word in a name string.

  Unlike `String.capitalize/1` which only capitalizes the first character of
  the whole string, this handles multi-word names like "mary jane" → "Mary Jane".
  """
  def title_case(nil), do: ""
  def title_case(""), do: ""

  def title_case(str) do
    str |> String.split() |> Enum.map_join(" ", &String.capitalize/1)
  end
end
