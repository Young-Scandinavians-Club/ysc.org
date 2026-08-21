defmodule YscWeb.AdminEventsLive.TicketReservationForm do
  use YscWeb, :live_component

  import YscWeb.AdminComponents

  alias Ysc.Events
  alias Ysc.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= if assigns[:ticket_reservation] do %>
          Edit Ticket Reservation
        <% else %>
          Reserve Tickets
        <% end %>
        <:subtitle>
          Reserve tickets from a ticket tier for a specific user
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="ticket-reservation-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="mt-8"
      >
        <.input type="hidden" field={@form[:ticket_tier_id]} />
        <.input type="hidden" field={@form[:created_by_id]} />
        <.admin_user_autocomplete
          id="ticket-reservation-user-autocomplete"
          label="User"
          name="ticket_reservation[user_id]"
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
          type="number"
          label="Discount Percentage (Optional)"
          field={@form[:discount_percentage]}
          placeholder="0"
          min="0"
          max="100"
          step="0.01"
        />
        <p class="text-sm text-zinc-500 mt-1">
          Optional discount percentage (e.g., 50 for 50% off)
        </p>

        <.input
          type="datetime-local"
          label="Expires At (Optional)"
          field={@form[:expires_at]}
        />
        <p class="text-sm text-zinc-500 mt-1">
          Leave empty for reservations that don't expire
        </p>

        <.input
          type="textarea"
          label="Notes (Optional)"
          field={@form[:notes]}
          placeholder="Internal notes about this reservation"
        />

        <:actions>
          <.button phx-disable-with="Saving...">Save Reservation</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(
        %{ticket_tier: ticket_tier, current_user: current_user} = assigns,
        socket
      ) do
    changeset =
      Events.TicketReservation.changeset(%Events.TicketReservation{}, %{
        ticket_tier_id: ticket_tier.id,
        created_by_id: current_user.id,
        status: "active",
        quantity: 1
      })

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:ticket_tier_id, ticket_tier.id)
     |> assign(:form, to_form(changeset))
     |> assign(:selected_user, nil)
     |> assign(:user_search, "")
     |> assign(:user_search_results, [])}
  end

  @impl true
  def update(assigns, socket) do
    ticket_tier_id =
      assigns[:ticket_tier_id] ||
        (assigns[:ticket_tier] && assigns[:ticket_tier].id)

    changeset =
      Events.TicketReservation.changeset(%Events.TicketReservation{}, %{
        ticket_tier_id: ticket_tier_id,
        created_by_id: assigns.current_user.id,
        status: "active",
        quantity: 1
      })

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:ticket_tier_id, ticket_tier_id)
     |> assign(:form, to_form(changeset))
     |> assign(:selected_user, nil)
     |> assign(:user_search, "")
     |> assign(:user_search_results, [])}
  end

  @impl true
  def handle_event(
        "validate",
        %{"ticket_reservation" => reservation_params},
        socket
      ) do
    # Get existing values from the current changeset to preserve them
    existing_changeset = socket.assigns.form.source

    existing_values = %{
      "quantity" => Ecto.Changeset.get_field(existing_changeset, :quantity),
      "discount_percentage" =>
        Ecto.Changeset.get_field(existing_changeset, :discount_percentage),
      "expires_at" => Ecto.Changeset.get_field(existing_changeset, :expires_at),
      "notes" => Ecto.Changeset.get_field(existing_changeset, :notes),
      "ticket_tier_id" => socket.assigns.ticket_tier_id,
      "created_by_id" => socket.assigns.current_user.id,
      "status" => "active"
    }

    # Merge existing values with new params (new params take precedence)
    merged_params = Map.merge(existing_values, reservation_params)

    # Preserve user_id if a user has been selected
    merged_params =
      if socket.assigns[:selected_user] do
        Map.put(merged_params, "user_id", socket.assigns.selected_user.id)
      else
        merged_params
      end

    changeset =
      %Events.TicketReservation{}
      |> Events.TicketReservation.changeset(merged_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("search-users", %{"value" => query}, socket) do
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

    # Get existing values from the current changeset to preserve them
    existing_changeset = socket.assigns.form.source

    params = %{
      "ticket_tier_id" => socket.assigns.ticket_tier_id,
      "created_by_id" => socket.assigns.current_user.id,
      "status" => "active",
      "user_id" => user.id,
      "quantity" => Ecto.Changeset.get_field(existing_changeset, :quantity),
      "discount_percentage" =>
        Ecto.Changeset.get_field(existing_changeset, :discount_percentage),
      "expires_at" => Ecto.Changeset.get_field(existing_changeset, :expires_at),
      "notes" => Ecto.Changeset.get_field(existing_changeset, :notes)
    }

    # Create a changeset with all preserved values plus the new user_id
    changeset =
      %Events.TicketReservation{}
      |> Events.TicketReservation.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:selected_user, user)
     |> assign(:user_search, "")
     |> assign(:user_search_results, [])
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("clear-user", _params, socket) do
    # Get existing values from the current changeset to preserve them
    existing_changeset = socket.assigns.form.source

    params = %{
      "ticket_tier_id" => socket.assigns.ticket_tier_id,
      "created_by_id" => socket.assigns.current_user.id,
      "status" => "active",
      "quantity" => Ecto.Changeset.get_field(existing_changeset, :quantity),
      "discount_percentage" =>
        Ecto.Changeset.get_field(existing_changeset, :discount_percentage),
      "expires_at" => Ecto.Changeset.get_field(existing_changeset, :expires_at),
      "notes" => Ecto.Changeset.get_field(existing_changeset, :notes)
    }

    # Create a changeset with all preserved values but without user_id
    changeset =
      %Events.TicketReservation{}
      |> Events.TicketReservation.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:selected_user, nil)
     |> assign(:user_search, "")
     |> assign(:user_search_results, [])
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event(
        "save",
        %{"ticket_reservation" => reservation_params},
        socket
      ) do
    ticket_tier_id =
      socket.assigns[:ticket_tier_id] ||
        (socket.assigns[:ticket_tier] && socket.assigns[:ticket_tier].id)

    # Include user_id if a user has been selected
    reservation_params =
      reservation_params
      |> Map.put("ticket_tier_id", ticket_tier_id)
      |> Map.put("created_by_id", socket.assigns.current_user.id)
      |> Map.put("status", "active")
      |> then(fn params ->
        if socket.assigns[:selected_user] do
          Map.put(params, "user_id", socket.assigns.selected_user.id)
        else
          params
        end
      end)
      |> normalize_expires_at()

    case Events.create_ticket_reservation(reservation_params) do
      {:ok, _reservation} ->
        # PubSub + parent LiveView send_update refresh the ticket tier UI and close the modal
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp normalize_expires_at(params) do
    case Map.get(params, "expires_at") do
      "" ->
        Map.put(params, "expires_at", nil)

      nil ->
        params

      expires_at when is_binary(expires_at) ->
        # Parse datetime-local format and convert to UTC
        case NaiveDateTime.from_iso8601("#{expires_at}:00") do
          {:ok, naive_dt} ->
            # Assume local timezone (PST) and convert to UTC
            local_dt = DateTime.from_naive!(naive_dt, "America/Los_Angeles")
            utc_dt = DateTime.shift_zone!(local_dt, "Etc/UTC")
            Map.put(params, "expires_at", utc_dt)

          {:error, _} ->
            Map.put(params, "expires_at", nil)
        end

      _ ->
        params
    end
  end
end
