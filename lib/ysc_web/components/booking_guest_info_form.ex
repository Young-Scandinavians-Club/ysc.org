defmodule YscWeb.Components.BookingGuestInfoForm do
  @moduledoc """
  Guest information form for Tahoe room bookings (checkout and modifications).
  """
  use YscWeb, :html

  alias YscWeb.BookingGuestForm

  attr :id, :string, default: "guest-info-form"
  attr :booking, :map, required: true
  attr :guest_info_form, :map, required: true
  attr :guest_info_errors, :map, default: %{}
  attr :other_family_members, :list, default: []
  attr :selected_family_members_for_guests, :map, default: %{}
  attr :current_user, :map, default: nil
  attr :submit_label, :string, default: "Continue"
  attr :intro_text, :string, default: nil

  slot :actions, doc: "Optional extra actions beside submit"

  def booking_guest_info_form(assigns) do
    ~H"""
    <div class="bg-white rounded-lg border border-zinc-200 p-8 shadow-sm">
      <h2 class="text-xl font-bold mb-2">Guest Information</h2>
      <p :if={@intro_text} class="text-sm text-zinc-600 mb-4">{@intro_text}</p>
      <p :if={!@intro_text} class="text-sm text-zinc-600 mb-4">
        Please provide details for everyone staying in {room_names(@booking)}.
      </p>

      <% booking_user_guest =
        if @guest_info_form do
          Enum.find(@guest_info_form.source, fn {_, guest_data} ->
            Map.get(guest_data, "is_booking_user") == true
          end)
        end %>
      <%= if booking_user_guest do %>
        <% {_, booking_user_data} = booking_user_guest %>
        <div class="mb-6 p-4 bg-blue-50 border-l-4 border-blue-500 rounded-r-lg">
          <div class="flex items-start gap-3">
            <div class="flex-shrink-0 w-10 h-10 rounded-full overflow-hidden ring-2 ring-blue-200">
              <%= if @current_user do %>
                <.user_avatar_image
                  user={@current_user}
                  class="w-full h-full object-cover"
                />
              <% else %>
                <.icon
                  name="hero-user-circle"
                  class="w-full h-full text-blue-600 p-2"
                />
              <% end %>
            </div>
            <div class="flex-1">
              <div class="flex items-center gap-2 mb-1">
                <p class="text-sm font-semibold text-blue-900">
                  You (the member making this booking)
                </p>
                <span class="px-2 py-0.5 bg-blue-100 text-blue-700 text-xs font-bold rounded">
                  Required
                </span>
              </div>
              <p class="text-sm text-blue-700 font-medium mb-2">
                {Map.get(booking_user_data, "first_name", "")} {Map.get(
                  booking_user_data,
                  "last_name",
                  ""
                )}
              </p>
              <p class="text-xs text-blue-600">
                As the member making this reservation, you must be present during the stay. You're already counted in the guest total above.
              </p>
            </div>
          </div>
        </div>
      <% end %>

      <%= if map_size(@guest_info_errors || %{}) > 0 do %>
        <% error_count =
          @guest_info_errors
          |> Enum.reject(fn {key, _} -> key == :general end)
          |> Enum.count() %>
        <%= if error_count > 0 do %>
          <div
            id="guest-errors-summary"
            role="alert"
            class="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg"
          >
            <p class="text-sm font-semibold text-red-800">
              {error_count} {if error_count == 1, do: "guest is", else: "guests are"} missing required information.
            </p>
          </div>
        <% end %>
      <% end %>

      <div
        :if={@guest_info_errors[:general]}
        class="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg"
        role="alert"
      >
        <p class="text-sm text-red-800">{@guest_info_errors[:general]}</p>
      </div>

      <form
        phx-change="validate-guest-info"
        phx-submit="save-guest-info"
        phx-debounce="300"
        id={@id}
      >
        <div class="space-y-6">
          <%= if @guest_info_form do %>
            <% {guests_count, children_count} = guest_counts(@booking) %>
            <% expected_total = guests_count + children_count %>
            <% guest_entries =
              @guest_info_form.source
              |> Enum.map(fn {index_str, guest_data} ->
                {String.to_integer(index_str), {index_str, guest_data}}
              end)
              |> Enum.sort_by(fn {order_index, _} -> order_index end)
              |> Enum.take(expected_total)
              |> Enum.map(fn {_order_index, entry} -> entry end) %>
            <% {booking_user_entries, non_booking_guests} =
              Enum.split_with(guest_entries, fn {_, guest_data} ->
                Map.get(guest_data, "is_booking_user") == true
              end) %>
            <%= for {index_str, guest_data} <- booking_user_entries do %>
              <input
                type="hidden"
                name={"guests[#{index_str}][first_name]"}
                value={Map.get(guest_data, "first_name", "")}
              />
              <input
                type="hidden"
                name={"guests[#{index_str}][last_name]"}
                value={Map.get(guest_data, "last_name", "")}
              />
              <input
                type="hidden"
                name={"guests[#{index_str}][is_child]"}
                value="false"
              />
              <input
                type="hidden"
                name={"guests[#{index_str}][is_booking_user]"}
                value="true"
              />
              <input
                type="hidden"
                name={"guests[#{index_str}][order_index]"}
                value={Map.get(guest_data, "order_index", 0)}
              />
            <% end %>
            <%= for {index_str, guest_data} <- non_booking_guests do %>
              <% index = String.to_integer(index_str) %>
              <% is_child = Map.get(guest_data, "is_child") == true %>
              <% selected_family_member_id =
                Map.get(@selected_family_members_for_guests || %{}, index_str) %>
              <% selected_family_member =
                if selected_family_member_id,
                  do:
                    Enum.find(@other_family_members || [], fn user ->
                      to_string(user.id) == to_string(selected_family_member_id)
                    end),
                  else: nil %>
              <% has_selected_family_member = not is_nil(selected_family_member) %>
              <% first_name =
                cond do
                  has_selected_family_member ->
                    selected_family_member.first_name || ""

                  true ->
                    Map.get(guest_data, "first_name", "")
                end %>
              <% last_name =
                cond do
                  has_selected_family_member ->
                    selected_family_member.last_name || ""

                  true ->
                    Map.get(guest_data, "last_name", "")
                end %>
              <div class={[
                "flex items-start gap-4 p-4 rounded-r-lg shadow-sm",
                if(is_child,
                  do: "bg-white border-l-4 border-green-500",
                  else: "bg-white border-l-4 border-blue-500"
                )
              ]}>
                <div class={[
                  "flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center font-bold text-sm",
                  if(is_child,
                    do: "bg-green-100 text-green-600",
                    else: "bg-blue-100 text-blue-600"
                  )
                ]}>
                  {index}
                </div>
                <div class="flex-1 space-y-3">
                  <div class="flex justify-between items-center">
                    <h3 class="font-bold text-zinc-800">
                      {if is_child, do: "Child Guest", else: "Adult Guest"}
                    </h3>
                    <%= if !is_child && length(@other_family_members || []) > 0 do %>
                      <select
                        id={"guest-#{index_str}-attendee-select"}
                        name={"guest-#{index_str}-attendee-select"}
                        phx-change="select-guest-attendee"
                        phx-debounce="100"
                        phx-value-guest-index={index_str}
                        value={
                          if has_selected_family_member,
                            do: "family_#{selected_family_member.id}",
                            else: "other"
                        }
                        class="text-xs border-none bg-zinc-100 rounded px-2 py-1 focus:outline-none focus:ring-2 focus:ring-blue-500"
                      >
                        <optgroup
                          :if={length(@other_family_members) > 0}
                          label="Family Members"
                        >
                          <option
                            :for={family_member <- @other_family_members}
                            value={"family_#{family_member.id}"}
                            selected={
                              has_selected_family_member &&
                                selected_family_member.id == family_member.id
                            }
                          >
                            {family_member.first_name} {family_member.last_name}
                          </option>
                        </optgroup>
                        <option value="other" selected={!has_selected_family_member}>
                          Someone else (Enter details)
                        </option>
                      </select>
                    <% end %>
                  </div>
                  <%= if !is_child && has_selected_family_member do %>
                    <div class="inline-flex items-center gap-2 px-3 py-1.5 bg-green-50 border border-green-200 rounded-lg">
                      <.icon
                        name="hero-check-circle"
                        class="w-5 h-5 text-green-600"
                      />
                      <span class="text-xs font-semibold text-green-800">
                        Guest: {selected_family_member.first_name} {selected_family_member.last_name}
                      </span>
                    </div>
                  <% else %>
                    <div class="grid grid-cols-2 gap-2">
                      <.input
                        type="text"
                        id={"guest-#{index_str}-first-name"}
                        name={"guests[#{index_str}][first_name]"}
                        value={first_name}
                        required
                        placeholder="First Name"
                        autocomplete="given-name"
                        errors={
                          if @guest_info_errors[index_str],
                            do: @guest_info_errors[index_str][:first_name] || [],
                            else: []
                        }
                      />
                      <.input
                        type="text"
                        id={"guest-#{index_str}-last-name"}
                        name={"guests[#{index_str}][last_name]"}
                        value={last_name}
                        required
                        placeholder="Last Name"
                        autocomplete="family-name"
                        errors={
                          if @guest_info_errors[index_str],
                            do: @guest_info_errors[index_str][:last_name] || [],
                            else: []
                        }
                      />
                    </div>
                  <% end %>
                </div>
                <input
                  type="hidden"
                  name={"guests[#{index_str}][is_child]"}
                  value={if is_child, do: "true", else: "false"}
                />
                <input
                  type="hidden"
                  name={"guests[#{index_str}][is_booking_user]"}
                  value="false"
                />
                <input
                  type="hidden"
                  name={"guests[#{index_str}][order_index]"}
                  value={index}
                />
              </div>
            <% end %>
          <% end %>
        </div>

        <div class="pt-6 border-t border-zinc-100 mt-6 space-y-4">
          <div class="flex flex-col sm:flex-row gap-4">
            <.button
              type="submit"
              phx-disable-with="Processing..."
              class="flex-1 w-full py-3"
              disabled={
                !BookingGuestForm.all_guests_valid?(@guest_info_form, @booking)
              }
            >
              {@submit_label}
              <.icon name="hero-arrow-right" class="w-5 h-5 -mt-0.5 ms-1" />
            </.button>
            {render_slot(@actions)}
          </div>
        </div>
      </form>
    </div>
    """
  end

  defp room_names(%{rooms: rooms}) when is_list(rooms) and rooms != [] do
    Enum.map_join(rooms, ", ", & &1.name)
  end

  defp room_names(_), do: "your selected room"

  defp guest_counts(booking) do
    guests_count = booking.guests_count || 1
    children_count = booking.children_count || 0
    {guests_count, children_count}
  end
end
