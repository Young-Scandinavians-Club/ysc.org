defmodule YscWeb.BookingGuestForm do
  @moduledoc """
  Shared guest information form helpers for Tahoe room bookings.
  Used by checkout and reservation modification flows.
  """

  alias Ysc.Accounts.User
  alias Ysc.Bookings.{Booking, BookingGuest}

  @doc """
  Returns true when a modification increases guest counts on a Tahoe room booking.
  """
  def guest_info_required_for_modification?(
        %Booking{property: :tahoe, booking_mode: :room} = booking,
        parsed
      ) do
    new_total = parsed.guests_count + parsed.children_count
    old_total = booking.guests_count + (booking.children_count || 0)
    new_total > old_total
  end

  def guest_info_required_for_modification?(_, _), do: false

  @doc """
  Initializes guest forms for a new booking checkout.
  """
  def initialize_guest_forms(%Booking{} = booking, %User{} = user) do
    {guests_count, children_count} = guest_counts(booking)
    build_form(guests_count, children_count, user, %{})
  end

  @doc """
  Initializes guest forms for a modification, pre-filling existing guests.
  """
  def initialize_modification_guest_forms(
        %Booking{} = booking,
        %User{} = user,
        guests_count,
        children_count
      ) do
    base_form = build_form(guests_count, children_count, user, %{})
    existing = booking.booking_guests || []

    booking_user = Enum.find(existing, & &1.is_booking_user)

    {existing_adults, existing_children} =
      existing
      |> Enum.reject(& &1.is_booking_user)
      |> Enum.split_with(fn guest -> not guest.is_child end)

    existing_adults = Enum.sort_by(existing_adults, & &1.order_index)
    existing_children = Enum.sort_by(existing_children, & &1.order_index)

    {merged_source, _adults, _children} =
      base_form.source
      |> Enum.sort_by(fn {_index_str, guest} ->
        Map.get(guest, "order_index") || 0
      end)
      |> Enum.reduce({%{}, existing_adults, existing_children}, fn
        {index_str, guest_data}, {acc, adults, children} ->
          {merged, adults, children} =
            cond do
              guest_data["is_booking_user"] == true ->
                merged =
                  if booking_user do
                    Map.merge(guest_data, guest_to_form_data(booking_user))
                  else
                    guest_data
                  end

                {merged, adults, children}

              guest_data["is_child"] == true ->
                case children do
                  [child | rest] ->
                    {Map.merge(guest_data, guest_to_form_data(child)), adults,
                     rest}

                  [] ->
                    {guest_data, adults, children}
                end

              true ->
                case adults do
                  [adult | rest] ->
                    {Map.merge(guest_data, guest_to_form_data(adult)), rest,
                     children}

                  [] ->
                    {guest_data, adults, children}
                end
            end

          {Map.put(acc, index_str, merged), adults, children}
      end)

    %{base_form | source: merged_source}
  end

  @doc """
  Returns a booking struct with updated guest counts for validation/display.
  """
  def preview_booking(%Booking{} = booking, guests_count, children_count) do
    %{booking | guests_count: guests_count, children_count: children_count}
  end

  @doc """
  Merges submitted guest params with the current form and family member selections.
  """
  def merge_guest_params(
        guest_info_form,
        guest_params,
        selected_family_members,
        other_family_members
      ) do
    guest_info_form =
      guest_info_form || Phoenix.Component.to_form(%{}, as: "guests")

    updated_guest_params =
      guest_params
      |> apply_family_member_selections(
        selected_family_members,
        other_family_members
      )

    guest_info_form.source
    |> Map.merge(updated_guest_params, fn _key, source_data, submitted_data ->
      source_data
      |> Map.merge(submitted_data)
      |> normalize_guest_field("is_child", false)
      |> normalize_guest_field("is_booking_user", false)
      |> normalize_guest_field("order_index", 0)
    end)
  end

  @doc """
  Validates guest params and returns an updated form plus field errors.
  """
  def validate_guest_params(%Booking{} = booking, guest_params)
      when is_map(guest_params) do
    updated_form = Phoenix.Component.to_form(guest_params, as: "guests")

    case build_guest_changesets(booking, guest_params) do
      {:ok, _changesets} ->
        {:ok, updated_form, %{}}

      {:error, invalid_changesets} when is_list(invalid_changesets) ->
        {:error, updated_form,
         errors_from_changesets(guest_params, invalid_changesets)}

      {:error, message} when is_binary(message) ->
        {:error, updated_form, %{general: message}}
    end
  end

  @doc """
  Returns true when every guest has a first and last name.
  """
  def all_guests_valid?(nil, _booking), do: false

  def all_guests_valid?(guest_info_form, %Booking{} = booking) do
    {guests_count, children_count} = guest_counts(booking)
    total_expected = guests_count + children_count

    if map_size(guest_info_form.source) != total_expected do
      false
    else
      Enum.all?(guest_info_form.source, fn {_index, guest_data} ->
        String.trim(guest_field(guest_data, "first_name")) != "" &&
          String.trim(guest_field(guest_data, "last_name")) != ""
      end)
    end
  end

  @doc """
  Replaces all guests on a booking from validated params.
  """
  def save_guests(%Booking{} = booking, guest_params)
      when is_map(guest_params) do
    with {:ok, changesets} <- build_guest_changesets(booking, guest_params) do
      persist_guest_changesets(booking.id, changesets)
    end
  end

  @doc """
  Persists guest records after a modification is applied.

  Uses guest params stored on the modification hold when present; otherwise trims
  excess guests when counts decreased.
  """
  def sync_guests_after_modification_apply(
        %Booking{} = updated_booking,
        hold_attrs,
        %Booking{} = original_booking,
        opts \\ []
      ) do
    guest_params =
      Keyword.get(opts, :guest_params) || hold_guest_params(hold_attrs)

    cond do
      is_map(guest_params) and map_size(guest_params) > 0 ->
        preview =
          preview_booking(
            updated_booking,
            updated_booking.guests_count,
            updated_booking.children_count || 0
          )

        save_guests(preview, guest_params)

      guest_counts_changed?(original_booking, updated_booking) ->
        trim_guests_to_counts(
          updated_booking.id,
          updated_booking.guests_count,
          updated_booking.children_count || 0
        )

      true ->
        :ok
    end
  end

  @doc """
  Removes guest records above the new total count after a decrease.
  """
  def trim_guests_to_counts(booking_id, guests_count, children_count) do
    total = guests_count + children_count

    import Ecto.Query
    alias Ysc.Repo

    from(bg in BookingGuest,
      where: bg.booking_id == ^booking_id and bg.order_index >= ^total
    )
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Handles family member selection for a guest row.
  """
  def select_guest_attendee(
        guest_info_form,
        guest_index,
        selected_value,
        other_family_members
      ) do
    guest_info_form =
      guest_info_form || Phoenix.Component.to_form(%{}, as: "guests")

    {selected_family_members_update, updated_form} =
      cond do
        selected_value == "other" ->
          updated_source =
            Map.put(guest_info_form.source, guest_index, %{
              "first_name" => "",
              "last_name" => "",
              "is_child" =>
                guest_field(
                  guest_info_form.source[guest_index] || %{},
                  "is_child"
                ),
              "is_booking_user" =>
                guest_field(
                  guest_info_form.source[guest_index] || %{},
                  "is_booking_user"
                ),
              "order_index" =>
                guest_field(
                  guest_info_form.source[guest_index] || %{},
                  "order_index"
                ) ||
                  String.to_integer(guest_index)
            })

          {Map.put(%{}, guest_index, nil),
           %{guest_info_form | source: updated_source}}

        is_binary(selected_value) and
            String.starts_with?(selected_value, "family_") ->
          user_id_str = String.replace(selected_value, "family_", "")

          selected_user =
            Enum.find(other_family_members, fn user ->
              to_string(user.id) == user_id_str
            end)

          if selected_user do
            existing = Map.get(guest_info_form.source, guest_index, %{})

            form_data = %{
              "first_name" => selected_user.first_name || "",
              "last_name" => selected_user.last_name || "",
              "is_child" => guest_field(existing, "is_child"),
              "is_booking_user" => guest_field(existing, "is_booking_user"),
              "order_index" =>
                guest_field(existing, "order_index") ||
                  String.to_integer(guest_index)
            }

            updated_source =
              Map.put(guest_info_form.source, guest_index, form_data)

            {Map.put(%{}, guest_index, selected_user.id),
             %{guest_info_form | source: updated_source}}
          else
            {%{}, guest_info_form}
          end

        true ->
          {%{}, guest_info_form}
      end

    {updated_form, selected_family_members_update}
  end

  @doc """
  Loads family members for guest selection dropdowns.
  """
  def load_family_members(%User{} = user) do
    family_members = Ysc.Accounts.get_family_group(user)

    other_family_members =
      Enum.reject(family_members, fn member -> member.id == user.id end)

    {family_members, other_family_members}
  end

  defp build_form(guests_count, children_count, user, existing_by_index) do
    user_guest = %{
      "first_name" => user.first_name || "",
      "last_name" => user.last_name || "",
      "is_child" => false,
      "is_booking_user" => true,
      "order_index" => 0
    }

    remaining_adults = max(0, guests_count - 1)

    additional_guests =
      build_guest_list(remaining_adults, children_count, 1)

    guest_params =
      ([user_guest] ++ additional_guests)
      |> Enum.map(fn guest ->
        order_index = Map.get(guest, "order_index") || 0
        merged = Map.merge(guest, Map.get(existing_by_index, order_index, %{}))
        {Integer.to_string(order_index), merged}
      end)
      |> Map.new()
      |> take_expected_guests(guests_count + children_count)

    Phoenix.Component.to_form(guest_params, as: "guests")
  end

  defp take_expected_guests(guest_params, expected_total) do
    guest_params
    |> Enum.map(fn {index_str, guest} ->
      order_index =
        Map.get(guest, "order_index") || String.to_integer(index_str)

      {order_index, {index_str, guest}}
    end)
    |> Enum.sort_by(fn {order_index, _} -> order_index end)
    |> Enum.take(expected_total)
    |> Enum.map(fn {_order_index, {index_str, guest}} -> {index_str, guest} end)
    |> Map.new()
  end

  defp build_guest_list(remaining_adults, remaining_children, start_index) do
    adults =
      if remaining_adults > 0 do
        Enum.map(0..(remaining_adults - 1), fn i ->
          %{
            "first_name" => "",
            "last_name" => "",
            "is_child" => false,
            "is_booking_user" => false,
            "order_index" => start_index + i
          }
        end)
      else
        []
      end

    children =
      if remaining_children > 0 do
        Enum.map(0..(remaining_children - 1), fn i ->
          %{
            "first_name" => "",
            "last_name" => "",
            "is_child" => true,
            "is_booking_user" => false,
            "order_index" => start_index + remaining_adults + i
          }
        end)
      else
        []
      end

    adults ++ children
  end

  defp build_guest_changesets(%Booking{} = booking, guest_params)
       when is_map(guest_params) do
    {guests_count, children_count} = guest_counts(booking)
    total_expected = guests_count + children_count

    guests_list =
      guest_params
      |> Enum.map(fn {index_str, guest_attrs} ->
        {String.to_integer(index_str), guest_attrs}
      end)
      |> Enum.sort_by(fn {index, _} -> index end)
      |> Enum.map(fn {_index, attrs} -> attrs end)

    cond do
      length(guests_list) != total_expected ->
        {:error,
         "Expected #{total_expected} guests, got #{length(guests_list)}"}

      booking_user_count(guests_list) != 1 ->
        {:error, "Exactly one guest must be marked as the booking user"}

      child_count(guests_list) != children_count ->
        {:error,
         "Expected #{children_count} children, got #{child_count(guests_list)}"}

      true ->
        changesets =
          Enum.map(guests_list, fn guest_attrs ->
            BookingGuest.changeset(
              %BookingGuest{},
              Map.merge(guest_attrs, %{"booking_id" => booking.id})
            )
          end)

        invalid =
          Enum.map(changesets, fn changeset ->
            if changeset.valid?, do: nil, else: changeset
          end)

        if Enum.all?(invalid, &is_nil/1) do
          {:ok, changesets}
        else
          {:error, invalid}
        end
    end
  end

  @dialyzer {:nowarn_function, persist_guest_changesets: 2}
  defp persist_guest_changesets(booking_id, changesets) do
    import Ecto.Query

    alias Ecto.Multi
    alias Ysc.Bookings.BookingGuest
    alias Ysc.Repo

    guests_attrs =
      Enum.map(changesets, fn changeset ->
        changes = Ecto.Changeset.apply_changes(changeset)
        order_index = Map.get(changes, :order_index) || 0

        attrs_map =
          changes
          |> Map.from_struct()
          |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
          |> Map.delete("order_index")

        {order_index, attrs_map}
      end)

    insert_multi =
      Enum.reduce(guests_attrs, Multi.new(), fn {index, guest_attrs}, acc ->
        guest_attrs_with_booking =
          Map.merge(guest_attrs, %{
            "booking_id" => booking_id,
            "order_index" => index
          })

        changeset =
          BookingGuest.changeset(%BookingGuest{}, guest_attrs_with_booking)

        Multi.insert(acc, {:guest, index}, changeset)
      end)

    multi =
      Multi.new()
      |> Multi.run(:delete, fn repo, _changes ->
        {count, _} =
          from(bg in BookingGuest, where: bg.booking_id == ^booking_id)
          |> repo.delete_all()

        {:ok, count}
      end)
      |> Multi.merge(fn _changes -> insert_multi end)

    case Repo.transaction(multi) do
      {:ok, _results} ->
        :ok

      {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  defp guest_to_form_data(%BookingGuest{} = guest) do
    %{
      "first_name" => guest.first_name || "",
      "last_name" => guest.last_name || "",
      "is_child" => guest.is_child,
      "is_booking_user" => guest.is_booking_user,
      "order_index" => guest.order_index
    }
  end

  defp apply_family_member_selections(
         guest_params,
         selected_family_members,
         other_family_members
       ) do
    Enum.map(guest_params, fn {index_str, guest_data} ->
      selected_family_member_id =
        Map.get(selected_family_members || %{}, index_str)

      updated_guest_data =
        if selected_family_member_id do
          selected_family_member =
            Enum.find(other_family_members || [], fn user ->
              to_string(user.id) == to_string(selected_family_member_id)
            end)

          if selected_family_member do
            Map.merge(guest_data, %{
              "first_name" => selected_family_member.first_name || "",
              "last_name" => selected_family_member.last_name || ""
            })
          else
            guest_data
          end
        else
          guest_data
        end

      {index_str, updated_guest_data}
    end)
    |> Map.new()
  end

  defp errors_from_changesets(guest_params, invalid_by_index)
       when is_list(invalid_by_index) do
    sorted_params =
      guest_params
      |> Enum.map(fn {index_str, guest_attrs} ->
        {String.to_integer(index_str), {index_str, guest_attrs}}
      end)
      |> Enum.sort_by(fn {index, _} -> index end)

    sorted_params
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {{_original_index, {index_str, _guest_attrs}}, idx},
                           acc ->
      case Enum.at(invalid_by_index, idx) do
        %Ecto.Changeset{} = changeset ->
          changeset_errors =
            Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
              Enum.reduce(opts, msg, fn {key, value}, error ->
                String.replace(error, "%{#{key}}", to_string(value))
              end)
            end)

          Map.put(acc, index_str, changeset_errors)

        _ ->
          acc
      end
    end)
  end

  defp guest_counts(%Booking{} = booking) do
    guests_count =
      case booking.guests_count do
        count when is_integer(count) and count > 0 -> count
        count when is_binary(count) -> String.to_integer(count)
        _ -> 1
      end

    children_count =
      case booking.children_count do
        count when is_integer(count) and count >= 0 -> count
        count when is_binary(count) -> String.to_integer(count)
        _ -> 0
      end

    {guests_count, children_count}
  end

  defp guest_field(guest_data, key) when is_map(guest_data) do
    Map.get(guest_data, key) || Map.get(guest_data, String.to_atom(key))
  end

  defp guest_field(_, _), do: nil

  defp normalize_guest_field(guest_data, key, default) do
    Map.update(guest_data, key, default, fn
      "true" -> true
      "false" -> false
      true -> true
      false -> false
      val when is_binary(val) and key == "order_index" -> String.to_integer(val)
      val when is_integer(val) -> val
      val -> val || default
    end)
  end

  defp booking_user_count(guests_list) do
    Enum.count(guests_list, fn guest ->
      guest_field(guest, "is_booking_user") in [true, "true"]
    end)
  end

  defp child_count(guests_list) do
    Enum.count(guests_list, fn guest ->
      guest_field(guest, "is_child") in [true, "true"]
    end)
  end

  defp hold_guest_params(%{"guest_params" => params}) when is_map(params), do: params
  defp hold_guest_params(_), do: nil

  defp guest_counts_changed?(%Booking{} = original, %Booking{} = updated) do
    original.guests_count != updated.guests_count ||
      (original.children_count || 0) != (updated.children_count || 0)
  end
end
