defmodule Ysc.WpMigration.BookingImport do
  @moduledoc """
  Resolves MotoPress Hotel Booking bookers during WordPress migration.

  MPHB stores `mphb_customer_id` as a **customer post** ID, not a WordPress user ID.
  When the customer post has no `_mphb_user_id` meta (true for the YSC backup), the
  booker must be resolved from `mphb_email` instead.
  """

  alias Ysc.Accounts
  alias Ysc.Accounts.User

  @doc """
  Resolves the WordPress user ID for a booking from MPHB export/repo data.

  Priority:
  1. `_mphb_user_id` on the linked customer post
  2. `mphb_email` matched against `wp_users.user_email`
  """
  def resolve_wp_user_id(
        customer_user_map,
        email_user_map,
        customer_post_id,
        email
      ) do
    cond do
      customer_post_id && Map.has_key?(customer_user_map, customer_post_id) ->
        Map.get(customer_user_map, customer_post_id)

      email = normalize_email(email) ->
        Map.get(email_user_map, email)

      true ->
        nil
    end
  end

  @doc """
  Resolves the migrated app `user_id` for a booking export row.

  Email is preferred because historical exports may contain a customer post ID
  incorrectly copied into `wp_customer_user_id`.
  """
  def resolve_migrated_user_id(row, user_map)
      when is_map(row) and is_map(user_map) do
    email = normalize_email(row["guest_email"])

    by_email =
      if email do
        case Accounts.get_user_by_email(email) do
          %User{id: id} -> id
          nil -> nil
        end
      end

    by_email || resolve_wp_customer_user_id(row, user_map)
  end

  defp resolve_wp_customer_user_id(row, user_map) do
    case row["wp_customer_user_id"] do
      nil ->
        nil

      wp_user_id ->
        post_id = row["wp_customer_post_id"]

        if post_id && to_string(wp_user_id) == to_string(post_id) do
          nil
        else
          user_map[wp_user_id]
        end
    end
  end

  @doc """
  Returns whether a guest row represents the booking member.
  """
  def guest_is_booking_user?(
        guest_first,
        guest_last,
        booking_user_first,
        booking_user_last
      ) do
    names_equal?(guest_first, booking_user_first) and
      names_equal?(guest_last, booking_user_last)
  end

  @doc false
  def normalize_email(nil), do: nil
  def normalize_email(""), do: nil

  def normalize_email(email) when is_binary(email) do
    email = String.trim(email)
    if email == "", do: nil, else: String.downcase(email)
  end

  def normalize_email(_), do: nil

  defp names_equal?(a, b) do
    String.downcase(String.trim(a || "")) ==
      String.downcase(String.trim(b || ""))
  end
end
