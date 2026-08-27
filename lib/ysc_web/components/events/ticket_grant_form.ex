defmodule YscWeb.AdminEventsLive.TicketGrantForm do
  use YscWeb, :live_component

  import YscWeb.AdminComponents

  alias Ysc.Accounts
  alias Ysc.Accounts.UserDisplay
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
          Double-check the member and quantity before granting; complimentary orders cannot be revoked from this screen.
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
        <.admin_user_autocomplete
          id="ticket-grant-user-autocomplete"
          label="Member"
          name="ticket_grant[user_id]"
          search_event="search-users"
          select_event="select-user"
          clear_event="clear-user"
          search_value={@user_search}
          results={@user_search_results}
          selected={@selected_user}
          errors={Enum.map(@form[:user_id].errors, &translate_error/1)}
          target={@myself}
          required
        />

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
          Allow granting when the tier or event is sold out. Publish status, sale windows, and event dates are still enforced.
        </p>

        <.input
          type="checkbox"
          field={@form[:skip_sale_guards]}
          label="Migration override"
        />
        <p class="text-sm text-zinc-500 -mt-2">
          Also bypass publish status, tier sale windows, and event date checks. Use only when importing tickets from a legacy system.
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
  def update(assigns, socket) do
    ticket_tier_id =
      case assigns do
        %{ticket_tier: %{id: id}} -> id
        _ -> assigns[:ticket_tier_id]
      end

    socket =
      socket
      |> assign_new(:admin_role, fn -> nil end)
      |> assign(assigns)
      |> assign(:ticket_tier_id, ticket_tier_id)

    if socket.assigns[:initialized?] do
      {:ok, socket}
    else
      {:ok,
       socket
       |> assign(:initialized?, true)
       |> assign(
         :form,
         to_form(default_form_params(ticket_tier_id), as: "ticket_grant")
       )
       |> assign(:selected_user, nil)
       |> assign(:user_search, "")
       |> assign(:user_search_results, [])}
    end
  end

  @impl true
  def handle_event("validate", %{"ticket_grant" => params}, socket) do
    merged = merge_form_params(socket, params)
    {:noreply, assign(socket, :form, to_form(merged, as: "ticket_grant"))}
  end

  @impl true
  def handle_event("search-users", %{"value" => query}, socket) do
    if socket.assigns[:admin_role] != :admin do
      {:noreply, socket}
    else
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
  end

  @impl true
  def handle_event("select-user", %{"id" => id}, socket) do
    if socket.assigns[:admin_role] != :admin do
      {:noreply, socket}
    else
      user = Accounts.get_user!(id)
      merged = merge_form_params(socket, %{"user_id" => user.id})

      {:noreply,
       socket
       |> assign(:selected_user, user)
       |> assign(:user_search, "")
       |> assign(:user_search_results, [])
       |> assign(:form, to_form(merged, as: "ticket_grant"))}
    end
  end

  @impl true
  def handle_event("clear-user", _params, socket) do
    merged = merge_form_params(socket, %{}) |> Map.delete("user_id")

    {:noreply,
     socket
     |> assign(:selected_user, nil)
     |> assign(:user_search, "")
     |> assign(:user_search_results, [])
     |> assign(:form, to_form(merged, as: "ticket_grant"))}
  end

  @impl true
  def handle_event("save", %{"ticket_grant" => params}, socket) do
    if socket.assigns[:admin_role] != :admin do
      {:noreply,
       YscWeb.Flash.put_toast(
         socket,
         :error,
         "You do not have permission to perform this action.",
         title: "Grant Tickets"
       )}
    else
      do_save_grant(params, socket)
    end
  end

  defp do_save_grant(params, socket) do
    merged = merge_form_params(socket, params)
    user_id = merged["user_id"]
    quantity = parse_quantity(merged["quantity"])
    skip_capacity? = checkbox_enabled?(merged["skip_capacity"])
    skip_sale_guards? = checkbox_enabled?(merged["skip_sale_guards"])
    skip_email? = not checkbox_enabled?(merged["send_email"])
    notes = blank_to_nil(merged["admin_grant_notes"])

    cond do
      is_nil(user_id) or user_id == "" ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(
           :error,
           "Select a member to grant tickets to.",
           title: "Grant Tickets"
         )
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
               skip_sale_guards: skip_sale_guards?,
               skip_email: skip_email?,
               admin_grant_notes: notes
             ) do
          {:ok, _order} ->
            user = socket.assigns.selected_user || Accounts.get_user!(user_id)

            send_update(TicketTierManagement,
              id: "ticket-tier-management-#{socket.assigns.event_id}",
              close_grant_modal: true,
              grant_success: %{
                user_name: UserDisplay.full_name(user),
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
      "skip_sale_guards" => false,
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

  defp checkbox_enabled?(value) do
    Phoenix.HTML.Form.normalize_value("checkbox", value) == "true"
  end

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

  defp grant_error_message(:tier_validation_failed),
    do: "Not enough tickets available in this tier."

  defp grant_error_message(:incomplete_member_profile),
    do:
      "This member's profile is missing a name or email required for registration tiers. Update their profile first."

  defp grant_error_message(:event_capacity_exceeded),
    do: "Event capacity would be exceeded."

  defp grant_error_message(:event_not_available),
    do:
      "Event must be published to grant tickets (enable migration override for legacy imports)."

  defp grant_error_message(:event_in_past),
    do:
      "Cannot grant tickets for events that have already started (enable migration override for legacy imports)."

  defp grant_error_message(:tier_not_on_sale),
    do:
      "This tier is not currently on sale (enable migration override for legacy imports)."

  defp grant_error_message(:event_cancelled),
    do: "This event has been cancelled."

  defp grant_error_message(:checkout_payment_in_progress),
    do:
      "This member has a payment in progress for this event. Wait for checkout to finish or fail before granting tickets."

  defp grant_error_message(other),
    do: "Could not grant tickets: #{inspect(other)}"
end
