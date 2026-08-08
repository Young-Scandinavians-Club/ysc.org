defmodule YscWeb.AdminMembershipHelpers do
  @moduledoc """
  Shared membership display helpers for admin LiveViews.
  """

  @doc """
  Human-readable membership type label.

  - `:short` — compact labels for check-in desks ("Lifetime", "Single", "Family")
  - `:full` — scanner and detail panels ("Lifetime Membership", ...)
  """
  @spec membership_type_label(term(), :short | :full) :: String.t()
  def membership_type_label(nil, :short), do: "Member"
  def membership_type_label(nil, :full), do: "Unknown"

  def membership_type_label(type, :short) when type in [:lifetime, "lifetime"],
    do: "Lifetime"

  def membership_type_label(type, :full) when type in [:lifetime, "lifetime"],
    do: "Lifetime Membership"

  def membership_type_label(type, :short) when type in [:single, "single"],
    do: "Single"

  def membership_type_label(type, :full) when type in [:single, "single"],
    do: "Single Membership"

  def membership_type_label(type, :short) when type in [:family, "family"],
    do: "Family"

  def membership_type_label(type, :full) when type in [:family, "family"],
    do: "Family Membership"

  def membership_type_label(type, :short) when is_atom(type) do
    type |> Atom.to_string() |> String.capitalize()
  end

  def membership_type_label(type, :short) when is_binary(type) do
    String.capitalize(type)
  end

  def membership_type_label(type, :full) when is_atom(type) do
    type |> Atom.to_string() |> String.capitalize() |> then(&"#{&1} Membership")
  end

  def membership_type_label(type, :full) when is_binary(type) do
    type |> String.capitalize() |> then(&"#{&1} Membership")
  end

  def membership_type_label(_, :short), do: "Member"
  def membership_type_label(_, :full), do: "Membership"
end
