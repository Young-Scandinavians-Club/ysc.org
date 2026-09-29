defmodule Ysc.Bookings.CabinMaster do
  @moduledoc """
  Looks up the cabin master for a property and formats contact details.

  Used by booking emails, the mobile property API, and member booking pages
  so name / mailbox / phone stay in one place.

  `email/1` returns the property mailbox (`tahoe@ysc.org` / `cl@ysc.org`) and
  `nil` for unknown properties. Member-facing mailto links that always need an
  address should use `Ysc.EmailConfig.booking_reply_to/1` instead, which falls
  back to the general contact address.
  """

  import Ecto.Query, warn: false

  alias Ysc.Accounts.User
  alias Ysc.EmailConfig
  alias Ysc.Extensions.PhoneNumber
  alias Ysc.Repo

  # Name, mailbox, and phone for emails/API. Skip hashes, bios, Stripe ids.
  @contact_fields [
    :id,
    :email,
    :first_name,
    :last_name,
    :phone_number,
    :board_position
  ]

  @doc """
  Returns the most recently updated user assigned as cabin master for `property`.

  Accepts `:tahoe` / `:clear_lake` atoms or `"tahoe"` / `"clear_lake"` strings.
  Selects contact columns only — not `hashed_password` / `board_bio`.
  """
  def get(property) do
    lookup(property, active_only?: false)
  end

  @doc """
  Like `get/1`, but only an `:active` cabin master.

  Booking modification and cancellation emails skip suspended/deleted holders.
  """
  def get_active(property) do
    lookup(property, active_only?: true)
  end

  @doc """
  Property mailbox for cabin-master correspondence, or `nil` when unknown.
  """
  def email(property) do
    case normalize_property(property) do
      :tahoe -> EmailConfig.tahoe_email()
      :clear_lake -> EmailConfig.clear_lake_email()
      _ -> nil
    end
  end

  @doc """
  Display contact map for emails and API copy.

  `email` is the property mailbox even when no cabin-master user is assigned.
  `name` and `phone` are `nil` when no user is found.
  """
  def contact(property) do
    contact_from_user(get(property), property)
  end

  @doc """
  Builds the contact map from an already-loaded cabin-master user.

  Use this when the caller already ran `get/1` or `get_active/1` so the
  properties API does not issue a second `users` SELECT.
  """
  def contact_from_user(user, property) do
    %{
      name: display_name(user),
      email: email(property),
      phone: display_phone(user)
    }
  end

  @doc false
  def ci_query_explain_query do
    cabin_master_query(:tahoe_cabin_master)
  end

  @doc false
  def ci_query_explain_active_query do
    cabin_master_query(:tahoe_cabin_master, active_only?: true)
  end

  defp lookup(property, opts) do
    case board_position(property) do
      nil ->
        nil

      position ->
        Repo.one(cabin_master_query(position, opts))
    end
  end

  defp cabin_master_query(board_position, opts \\ []) do
    query =
      from(u in User,
        where: u.board_position == ^board_position,
        select: struct(u, ^@contact_fields),
        order_by: [desc: u.updated_at],
        limit: 1
      )

    if Keyword.get(opts, :active_only?, false) do
      from(u in query, where: u.state == :active)
    else
      query
    end
  end

  defp board_position(property) do
    case normalize_property(property) do
      :tahoe -> :tahoe_cabin_master
      :clear_lake -> :clear_lake_cabin_master
      _ -> nil
    end
  end

  defp normalize_property(:tahoe), do: :tahoe
  defp normalize_property(:clear_lake), do: :clear_lake
  defp normalize_property("tahoe"), do: :tahoe
  defp normalize_property("clear_lake"), do: :clear_lake
  defp normalize_property(_), do: nil

  defp display_name(nil), do: nil

  defp display_name(user) do
    "#{user.first_name || ""} #{user.last_name || ""}"
    |> String.trim()
  end

  defp display_phone(nil), do: nil

  defp display_phone(user) do
    PhoneNumber.format_for_display(user.phone_number) || user.phone_number
  end
end
