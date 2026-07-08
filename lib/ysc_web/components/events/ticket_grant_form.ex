defmodule YscWeb.AdminEventsLive.TicketGrantForm do
  use YscWeb, :live_component

  alias Ysc.Accounts
  alias Ysc.Tickets
  alias YscWeb.AdminEventsLive.TicketTierManagement

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        Grant Tickets
        <:subtitle>
          Immediately assign confirmed tickets to a member (e.g. migration from a legacy system).
          To revoke a mistaken grant, cancel the ticket order from Admin → Money.
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="ticket-grant-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="mt-8"
      >
        <.input type="hidden" field={@form[:ticket_tier_id]} />
        <!-- User Search -->
        <div class="space-y-2">
          <label class="block text-sm font-semibold leading-6 text-zinc-800">
            Member
          </label>
          <div
            :if={@selected_user}
            class="flex items-center justify-between p-3 bg-zinc-50 rounded-lg border border-zinc-200"
          >
            <div>
              <p class="font-medium text-zinc-900">
                {@selected_user.first_name} {@selected_user.last_name}
              </p>
              <p class="text-sm text-zinc-600">{@selected_user.email}</p>
            </div>
            <button
              type="button"
              phx-click="clear-user"
              phx-target={@myself}
              class="text-zinc-400 hover:text-red-600"
              title="Clear member"
            >
              <.icon name="hero-x-mark" class="w-5 h-5" />
            </button>
          </div>
          <div :if={!@selected_user} class="space-y-2">
            <input
              type="text"
              phx-debounce="200"
              phx-target={@myself}
              phx-change="search-users"
              name="user_search"
              placeholder="Search by name or email..."
              value={@user_search}
              class="block w-full rounded-md border-0 py-1.5 text-zinc-900 shadow-sm ring-1 ring-inset ring-zinc-300 placeholder:text-zinc-400 focus:ring-2 focus:ring-inset focus:ring-blue-600 sm:text-sm sm:leading-6"
            />
            <div
              :if={length(@user_search_results) > 0}
              class="border border-zinc-200 rounded-lg bg-white shadow-lg max-h-60 overflow-y-auto"
            >
              <div
                :for={user <- @user_search_results}
                phx-click="select-user"
                phx-value-id={user.id}
                phx-target={@myself}
                class="p-3 hover:bg-zinc-50 cursor-pointer border-b border-zinc-100 last:border-b-0"
              >
                <p class="font-medium text-zinc-900">
                  {user.first_name} {user.last_name}
                </p>
                <p class="text-sm text-zinc-600">{user.email}</p>
              </div>
            </div>
          </div>
          <.error :for={error <- @form[:user_id].errors}>
            {translate_error(error)}
          </.error>
        </div>

        <.input
          type="number"
          label="Quantity"
          field={@form[:quantity]}
          placeholder="1"
          min="1"
          required
        />

        <.input
          type="checkbox"
          field={@form[:skip_capacity]}
          label="Override capacity limits"
        />
        <p class="text-sm text-zinc-500 -mt-2">
          Allow granting even when the tier or event is sold out (useful for migration).
        </p>

        <.input
          type="checkbox"
          field={@form[:send_email]}
          label="Send ticket confirmation email"
        />

        <.input
          type="textarea"
          label="Notes (Optional)"
          field={@form[:admin_grant_notes]}
          placeholder="e.g. Migrated from legacy order #12345"
        />

        <:actions>
          <.button phx-disable-with="Granting...">Grant Tickets</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{ticket_tier: ticket_tier} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:ticket_tier_id, ticket_tier.id)
     |> assign(
       :form,
       to_form(default_form_params(ticket_tier.id), as: "ticket_grant")
     )
     |> assign(:selected_user, nil)
     |> assign(:user_search, "")
     |> assign(:user_search_results, [])}
  end

  @impl true
  def update(assigns, socket) do
    ticket_tier_id =
      assigns[:ticket_tier_id] ||
        (assigns[:ticket_tier] && assigns[:ticket_tier].id)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:ticket_tier_id, ticket_tier_id)
     |> assign(
       :form,
       to_form(default_form_params(ticket_tier_id), as: "ticket_grant")
     )
     |> assign(:selected_user, nil)
     |> assign(:user_search, "")
     |> assign(:user_search_results, [])}
  end

  @impl true
  def handle_event("validate", %{"ticket_grant" => params}, socket) do
    merged = merge_form_params(socket, params)
    {:noreply, assign(socket, :form, to_form(merged, as: "ticket_grant"))}
  end

  @impl true
  def handle_event("search-users", %{"user_search" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Accounts.search_users(query, limit: 10)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:user_search, query)
     |> assign(:user_search_results, results)}
  end

  @impl true
  def handle_event("select-user", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)
    merged = merge_form_params(socket, %{"user_id" => user.id})

    {:noreply,
     socket
     |> assign(:selected_user, user)
     |> assign(:user_search, "")
     |> assign(:user_search_results, [])
     |> assign(:form, to_form(merged, as: "ticket_grant"))}
  end

  @impl true
  def handle_event("clear-user", _params, socket) do
    merged = merge_form_params(socket, %{}) |> Map.delete("user_id")

    {:noreply,
     socket
     |> assign(:selected_user, nil)
     |> assign(:form, to_form(merged, as: "ticket_grant"))}
  end

  @impl true
  def handle_event("save", %{"ticket_grant" => params}, socket) do
    merged = merge_form_params(socket, params)
    user_id = merged["user_id"]
    quantity = parse_quantity(merged["quantity"])
    skip_capacity? = merged["skip_capacity"] == "true"
    skip_email? = merged["send_email"] != "true"
    notes = blank_to_nil(merged["admin_grant_notes"])

    cond do
      is_nil(user_id) or user_id == "" ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Select a member to grant tickets to.", title: "Grant Tickets")
         |> assign(:form, to_form(merged, as: "ticket_grant"))}

      is_nil(quantity) or quantity < 1 ->
        {:noreply,
         assign(
           socket,
           :form,
           to_form(Map.put(merged, "quantity", ""), as: "ticket_grant")
         )}

      true ->
        ticket_selections = %{socket.assigns.ticket_tier_id => quantity}

        case Tickets.grant_admin_tickets(
               socket.assigns.current_user.id,
               user_id,
               socket.assigns.event_id,
               ticket_selections,
               skip_capacity: skip_capacity?,
               skip_email: skip_email?,
               admin_grant_notes: notes
             ) do
          {:ok, _order} ->
            user = socket.assigns.selected_user || Accounts.get_user!(user_id)

            send_update(TicketTierManagement,
              id: "ticket-tier-management-#{socket.assigns.event_id}",
              close_grant_modal: true,
              grant_success: %{
                user_name: "#{user.first_name} #{user.last_name}",
                quantity: quantity
              }
            )

            {:noreply, socket}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply,
             assign(socket, :form, to_form(changeset, as: "ticket_grant"))}

          {:error, reason} ->
            {:noreply,
             socket
             |> YscWeb.Flash.put_toast(
               :error,
               grant_error_message(reason),
               title: "Grant Tickets"
             )}
        end
    end
  end

  defp default_form_params(ticket_tier_id) do
    %{
      "ticket_tier_id" => ticket_tier_id,
      "quantity" => 1,
      "skip_capacity" => false,
      "send_email" => true,
      "admin_grant_notes" => ""
    }
  end

  defp merge_form_params(socket, params) do
    existing =
      socket.assigns.form.params ||
        default_form_params(socket.assigns.ticket_tier_id)

    merged =
      existing
      |> Map.merge(params)
      |> Map.put("ticket_tier_id", socket.assigns.ticket_tier_id)

    if socket.assigns[:selected_user] do
      Map.put(merged, "user_id", socket.assigns.selected_user.id)
    else
      merged
    end
  end

  defp parse_quantity(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_quantity(value) when is_integer(value), do: value
  defp parse_quantity(_), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp grant_error_message(:user_not_found), do: "Member not found."
  defp grant_error_message(:event_not_found), do: "Event not found."

  defp grant_error_message(:partiful_event),
    do: "Cannot grant tickets for Partiful events."

  defp grant_error_message(:donation_tier_not_grantable),
    do: "Donation tiers cannot be granted."

  defp grant_error_message(:invalid_ticket_tier), do: "Invalid ticket tier."

  defp grant_error_message(:invalid_quantity),
    do: "Quantity must be at least 1."

  defp grant_error_message(:empty_selection), do: "Select at least one ticket."

  defp grant_error_message(:insufficient_capacity),
    do: "Not enough tickets available in this tier."

  defp grant_error_message(:event_capacity_exceeded),
    do: "Event capacity would be exceeded."

  defp grant_error_message(:event_not_available),
    do:
      "Event must be published to grant tickets (or enable override capacity)."

  defp grant_error_message(:event_in_past),
    do: "Cannot grant tickets for events that have already started."

  defp grant_error_message(:event_cancelled),
    do: "This event has been cancelled."

  defp grant_error_message(other),
    do: "Could not grant tickets: #{inspect(other)}"
end
