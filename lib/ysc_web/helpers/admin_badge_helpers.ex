defmodule YscWeb.AdminBadgeHelpers do
  @moduledoc """
  Maps admin domain values to `<.badge type={...}>` strings shared across admin LiveViews.

  Message type helpers align with `MessageType` (`:email`, `:sms`) from `Ysc.Messages`.
  """

  @doc """
  Badge `type` for `Ysc.Accounts.User` state atoms (users list and detail panels).
  """
  @spec user_state_badge_type(atom()) :: String.t()
  def user_state_badge_type(:active), do: "green"
  def user_state_badge_type(:pending_approval), do: "yellow"
  def user_state_badge_type(:rejected), do: "red"
  def user_state_badge_type(:suspended), do: "red"
  def user_state_badge_type(:deleted), do: "dark"
  def user_state_badge_type(_), do: "default"

  @doc """
  Badge `type` for membership application review outcomes.
  """
  @spec review_outcome_badge_type(atom()) :: String.t()
  def review_outcome_badge_type(:approved), do: "green"
  def review_outcome_badge_type(:rejected), do: "red"
  def review_outcome_badge_type(_), do: "default"

  @doc """
  Badge `type` for idempotency / notification `message_type` (`:email` or `:sms`).
  """
  @spec message_type_badge_type(atom()) :: String.t()
  def message_type_badge_type(:email), do: "default"
  def message_type_badge_type(:sms), do: "green"
  def message_type_badge_type(_), do: "default"

  @doc """
  Human-readable label for a message type.

  - `:table` — uppercase (notification list rows)
  - `:detail` — sentence case (side panel)
  """
  @spec message_type_label(atom(), :table | :detail) :: String.t()
  def message_type_label(message_type, :table) do
    message_type
    |> Atom.to_string()
    |> String.upcase()
  end

  def message_type_label(message_type, :detail) do
    message_type
    |> Atom.to_string()
    |> String.capitalize()
  end

  @doc """
  Recipient email or formatted phone for a notification row, or `nil` when absent.
  """
  @spec message_recipient_text(map()) :: String.t() | nil
  def message_recipient_text(%{email: email})
      when is_binary(email) and email != "" do
    email
  end

  def message_recipient_text(%{phone_number: phone}) when not is_nil(phone) do
    Ysc.Extensions.PhoneNumber.format_for_display(phone) || phone
  end

  def message_recipient_text(_), do: nil

  @doc """
  Badge `type` for booking status in admin lists and detail panels.
  """
  @spec booking_status_badge_type(atom()) :: String.t()
  def booking_status_badge_type(:complete), do: "green"
  def booking_status_badge_type(:canceled), do: "red"
  def booking_status_badge_type(:refunded), do: "yellow"
  def booking_status_badge_type(:hold), do: "sky"
  def booking_status_badge_type(:draft), do: "dark"
  def booking_status_badge_type(_), do: "dark"

  @doc """
  Badge `type` for ledger payment or refund status in admin booking views.
  """
  @spec ledger_payment_status_badge_type(atom()) :: String.t()
  def ledger_payment_status_badge_type(:completed), do: "green"
  def ledger_payment_status_badge_type(:pending), do: "yellow"
  def ledger_payment_status_badge_type(:failed), do: "red"
  def ledger_payment_status_badge_type(:refunded), do: "zinc"
  def ledger_payment_status_badge_type(_), do: "dark"

  @doc """
  Badge `type` for expense report status in admin money and event views.
  """
  @spec expense_report_status_badge_type(String.t() | atom() | nil) ::
          String.t()
  def expense_report_status_badge_type(status) do
    case String.downcase(to_string(status || "")) do
      "draft" -> "dark"
      "submitted" -> "default"
      "approved" -> "green"
      "rejected" -> "red"
      "paid" -> "sky"
      _ -> "dark"
    end
  end

  @doc """
  Badge `type` for Stripe payout status in admin money views.
  """
  @spec payout_status_badge_type(String.t() | atom() | nil) :: String.t()
  def payout_status_badge_type(status) do
    case String.downcase(to_string(status || "")) do
      "paid" -> "green"
      "pending" -> "yellow"
      "failed" -> "red"
      "canceled" -> "zinc"
      _ -> "dark"
    end
  end

  @doc """
  Badge `type` for `PostState` values in admin posts list and editor views.
  """
  @spec post_state_badge_type(atom()) :: String.t()
  def post_state_badge_type(:draft), do: "yellow"
  def post_state_badge_type(:published), do: "green"
  def post_state_badge_type(:deleted), do: "red"
  def post_state_badge_type(_), do: "default"

  @doc """
  Badge `type` for `EventState` values in admin event previews and lists.
  """
  @spec event_state_badge_type(atom()) :: String.t()
  def event_state_badge_type(:draft), do: "sky"
  def event_state_badge_type(:scheduled), do: "yellow"
  def event_state_badge_type(:published), do: "green"
  def event_state_badge_type(_), do: "default"

  @doc """
  Badge `type` for a newsletter subscriber's `source` string (admin subscribers list).

  Unrecognized sources fall back to `"default"` so new source values introduced
  elsewhere in the app still render (just uncategorized by color).
  """
  @spec newsletter_source_badge_type(String.t() | nil) :: String.t()
  def newsletter_source_badge_type("public_signup"), do: "green"
  def newsletter_source_badge_type("newsletters_page"), do: "green"
  def newsletter_source_badge_type("signup"), do: "green"
  def newsletter_source_badge_type("user_registration"), do: "sky"
  def newsletter_source_badge_type("user_registration_linked"), do: "sky"
  def newsletter_source_badge_type("user_settings"), do: "sky"
  def newsletter_source_badge_type("email_change"), do: "sky"
  def newsletter_source_badge_type("admin_added"), do: "yellow"
  def newsletter_source_badge_type("wp_migration"), do: "zinc"
  def newsletter_source_badge_type("hard_bounce"), do: "red"
  def newsletter_source_badge_type(_), do: "default"

  @doc """
  Human-readable label for a newsletter subscriber's `source` string,
  e.g. `"public_signup"` -> `"Public signup"`. Returns `"Unknown"` for `nil`/empty.
  """
  @spec newsletter_source_label(String.t() | nil) :: String.t()
  def newsletter_source_label(nil), do: "Unknown"
  def newsletter_source_label(""), do: "Unknown"

  def newsletter_source_label(source) when is_binary(source) do
    source
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
