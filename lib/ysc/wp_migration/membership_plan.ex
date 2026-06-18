defmodule Ysc.WpMigration.MembershipPlan do
  @moduledoc """
  Normalizes WordPress membership plans to `"single"` or `"family"`.

  Priority when resolving during load:

  1. WooCommerce Membership / Subscription product name from WP
  2. Signup application `membership_type`
  3. User usermeta `membership_type`
  """

  @doc """
  Infers `"single"` or `"family"` from a WooCommerce product title.
  """
  def from_product_name(nil), do: nil
  def from_product_name(""), do: nil

  def from_product_name(name) when is_binary(name) do
    normalized =
      name
      |> String.downcase()
      |> String.trim()

    cond do
      String.contains?(normalized, "family") ->
        "family"

      String.contains?(normalized, "single") ->
        "single"

      true ->
        nil
    end
  end

  @doc """
  Normalizes application/usermeta membership type values.
  """
  def from_membership_type(nil), do: nil
  def from_membership_type(""), do: nil

  def from_membership_type(type) when is_binary(type) do
    case String.downcase(String.trim(type)) do
      "family" -> "family"
      "wc-family" -> "family"
      "single" -> "single"
      _ -> nil
    end
  end

  @doc """
  Resolves the plan for a migrated user.

  ## Options

  - `:membership_product_name` — preferred WP product title when already chosen
  - `:wcm_product_name` — WooCommerce Membership product title
  - `:sub_product_name` — product linked to the user's subscription
  - `:application_membership_type` — signup application value
  - `:user_membership_type` — usermeta membership type
  """
  def resolve(opts) when is_map(opts) do
    wp_product_name =
      first_present([
        opts[:membership_product_name],
        opts[:wcm_product_name],
        opts[:sub_product_name]
      ])

    from_product_name(wp_product_name) ||
      from_membership_type(opts[:application_membership_type]) ||
      from_membership_type(opts[:user_membership_type]) ||
      "single"
  end

  defp first_present(values) do
    Enum.find(values, fn
      value when is_binary(value) -> String.trim(value) != ""
      _ -> false
    end)
  end
end
