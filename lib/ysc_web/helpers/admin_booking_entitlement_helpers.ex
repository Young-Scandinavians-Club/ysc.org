defmodule YscWeb.AdminBookingEntitlementHelpers do
  @moduledoc """
  Shared booking entitlement display helpers for admin LiveViews.
  """

  alias Ysc.Bookings.BookingEntitlement

  @benefit_kind_options [
    {"percent_off", "Percent off stay",
     "e.g. 50% off, capped at a max $ discount"},
    {"free_nights", "Free nights", "A number of nights covered for free"},
    {"fixed_amount_off", "Fixed amount off", "A flat $ discount off the stay"}
  ]

  @property_select_options [
    {"Any property", ""},
    {"Lake Tahoe", "tahoe"},
    {"Clear Lake", "clear_lake"}
  ]

  @doc """
  Benefit kind options for the grant entitlement form (`value`, title, description).
  """
  @spec grant_benefit_kind_options() :: [{String.t(), String.t(), String.t()}]
  def grant_benefit_kind_options, do: @benefit_kind_options

  @doc """
  Property `<select>` options for the grant entitlement form.
  """
  @spec grant_property_select_options() :: [{String.t(), String.t()}]
  def grant_property_select_options, do: @property_select_options

  @doc """
  Current benefit kind from a grant entitlement form, defaulting to `"percent_off"`.
  """
  @spec benefit_kind_form_value(map()) :: String.t()
  def benefit_kind_form_value(form) do
    case form[:benefit_kind].value do
      nil -> "percent_off"
      value -> to_string(value)
    end
  end

  @doc """
  Human-readable entitlement status for admin tables.
  """
  @spec status_label(atom()) :: String.t()
  def status_label(:active), do: "Active"
  def status_label(:consumed), do: "Consumed"
  def status_label(:revoked), do: "Revoked"
  def status_label(:expired), do: "Expired"
  def status_label(other), do: to_string(other)

  @doc """
  Human-readable property label for entitlement tables.
  """
  @spec property_label(nil | atom()) :: String.t()
  def property_label(nil), do: "Any"
  def property_label(:tahoe), do: "Tahoe"
  def property_label(:clear_lake), do: "Clear Lake"

  @doc """
  Human-readable benefit summary for entitlement rows.

  - `:list` — org entitlements list (includes max guests for free nights)
  - `:user_detail` — user detail panel (includes buyout cap for free nights)
  """
  @spec benefit_summary(BookingEntitlement.t(), :list | :user_detail) ::
          String.t()
  def benefit_summary(
        %BookingEntitlement{benefit_kind: :free_nights} = ent,
        :list
      ) do
    "#{ent.free_nights} free night(s), max guests #{ent.max_guests || "—"}"
  end

  def benefit_summary(
        %BookingEntitlement{benefit_kind: :free_nights} = ent,
        :user_detail
      ) do
    "#{ent.free_nights || "?"} free night(s), buyout cap #{format_money(ent.buyout_max_discount)}"
  end

  def benefit_summary(
        %BookingEntitlement{benefit_kind: :percent_off} = ent,
        :list
      ) do
    percent = Decimal.round(ent.percent_off || Decimal.new(0), 0)

    "#{Decimal.to_string(percent)}% off, buyout cap #{format_money(ent.buyout_max_discount)}"
  end

  def benefit_summary(
        %BookingEntitlement{benefit_kind: :percent_off} = ent,
        :user_detail
      ) do
    percent = Decimal.to_string(ent.percent_off || Decimal.new(0))
    "#{percent}% off, buyout cap #{format_money(ent.buyout_max_discount)}"
  end

  def benefit_summary(
        %BookingEntitlement{benefit_kind: :fixed_amount_off} = ent,
        _context
      ) do
    "#{format_money(ent.amount_off)} off"
  end

  defp format_money(nil), do: "—"
  defp format_money(m), do: Ysc.MoneyHelper.format_money!(m)
end
