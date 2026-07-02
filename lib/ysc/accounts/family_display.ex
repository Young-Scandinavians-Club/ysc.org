defmodule Ysc.Accounts.FamilyDisplay do
  @moduledoc """
  Human-readable labels for family membership fields.

  Centralizes relationship/type formatting used across account settings,
  the member dashboard, and admin user detail views.
  """

  @doc """
  Returns a display label for a family relationship or member type.

  Accepts `FamilyMemberType` values as atoms (`:spouse`, `:child`) or strings
  (`"spouse"`, `"child"`). Unknown and nil values default to `"Child"`.
  """
  def relationship_label(nil), do: "Child"
  def relationship_label(:spouse), do: "Spouse"
  def relationship_label(:child), do: "Child"
  def relationship_label("spouse"), do: "Spouse"
  def relationship_label("child"), do: "Child"
  def relationship_label(_), do: "Child"
end
