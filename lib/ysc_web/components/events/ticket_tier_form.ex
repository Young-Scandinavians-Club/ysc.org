defmodule YscWeb.AdminEventsLive.TicketTierForm do
  use YscWeb, :live_component

  alias Ysc.Events.TicketTier

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"#{@event_id}-ticket-tier-form"}>
      <.form
        :let={_f}
        for={@form}
        as={:ticket_tier}
        id={@id}
        phx-submit="save"
        phx-target={@myself}
        phx-value-event_id={@event_id}
        phx-change="validate"
        class="space-y-4"
      >
        <.input type="hidden" value={@event_id} field={@form[:event_id]} />
        <.input
          type="select"
          label="Type"
          field={@form[:type]}
          options={[
            {"Free", "free"},
            {"Paid", "paid"},
            {"Donation", "donation"}
          ]}
          required
        />
        <.input type="text" label="Name" field={@form[:name]} required />

        <.input type="textarea" label="Description" field={@form[:description]} />

        <.input
          :if={paid_type?(@form[:type].value)}
          type="text"
          label="Price"
          field={@form[:price]}
          placeholder="0.00"
          phx-hook="MoneyInput"
          value={format_money(@form[:price].value)}
          required
        >
          <div class="text-zinc-800">
            $
          </div>
        </.input>
        <.input
          :if={!donation_type?(@form[:type].value)}
          type="checkbox"
          label="Unlimited quantity"
          field={@form[:unlimited_quantity]}
          phx-change="toggle_quantity_limit"
          phx-target={@myself}
        />

        <.input
          :if={
            !donation_type?(@form[:type].value) && !@form[:unlimited_quantity].value
          }
          type="number"
          label="Quantity"
          field={@form[:quantity]}
        />

        <.date_picker
          :if={!donation_type?(@form[:type].value)}
          id="sales_start"
          label="Sale Starts"
          form={@form}
          start_date_field={@form[:start_date]}
          min={Date.utc_today()}
          required={false}
        />
        <.date_picker
          :if={!donation_type?(@form[:type].value)}
          id="sale_ends"
          label="Sale Ends"
          form={@form}
          start_date_field={@form[:end_date]}
          min={sale_end_min_date(@form[:start_date].value)}
          required={false}
        />

        <div
          :if={!donation_type?(@form[:type].value)}
          phx-feedback-for={@form[:requires_registration].name}
        >
          <label class="flex items-center gap-4 text-sm leading-6 text-zinc-600">
            <input
              type="hidden"
              name={@form[:requires_registration].name}
              value="false"
            />
            <input
              type="checkbox"
              id={@form[:requires_registration].id}
              name={@form[:requires_registration].name}
              value="true"
              checked={
                Phoenix.HTML.Form.normalize_value(
                  "checkbox",
                  @form[:requires_registration].value
                )
              }
              class="rounded border-zinc-300 text-zinc-900 focus:ring-0"
            />
            <span class="flex items-center gap-2">
              Requires Registration
              <.tooltip
                max_width="max-w-2xl"
                tooltip_text="When enabled, customers will be required to provide first name, last name, and email for each ticket during checkout."
              >
                <.icon
                  name="hero-question-mark-circle"
                  class="w-4 h-4 text-zinc-400 hover:text-zinc-600"
                />
              </.tooltip>
            </span>
          </label>
          <.error :for={
            msg <-
              Enum.map(@form[:requires_registration].errors, &translate_error(&1))
          }>
            <%= msg %>
          </.error>
        </div>

        <div class="flex justify-end">
          <.button type="submit">
            <%= if assigns[:ticket_tier] do %>
              <.icon name="hero-pencil" class="me-1 -mt-0.5" /> Update Ticket Tier
            <% else %>
              <.icon name="hero-plus" class="me-1 -mt-0.5" /> Add Ticket Tier
            <% end %>
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    # Only create a new changeset if we don't already have one in the socket
    changeset =
      if socket.assigns[:form] do
        # Preserve existing form state
        socket.assigns.form.source
      else
        # Create new changeset only on initial load
        if assigns[:ticket_tier] do
          # Editing existing ticket tier
          ticket_tier = assigns.ticket_tier

          attrs = %{
            unlimited_quantity:
              is_nil(ticket_tier.quantity) or ticket_tier.quantity == 0
          }

          TicketTier.changeset(ticket_tier, attrs)
        else
          # Creating new ticket tier - default to free so price starts hidden
          TicketTier.changeset(%TicketTier{}, %{
            unlimited_quantity: false,
            type: :free
          })
        end
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("toggle_quantity_limit", params, socket) do
    # Handle both expected and unexpected parameter formats
    ticket_tier_params = params["ticket_tier"] || params

    # Merge with existing form values to preserve fields like name, type, etc.
    existing_values = get_existing_form_values(socket.assigns.form)
    merged_params = Map.merge(existing_values, ticket_tier_params)

    merged_params =
      merged_params
      |> maybe_parse_price()
      |> maybe_set_free_price()
      |> maybe_set_unlimited_quantity()

    changeset =
      if socket.assigns[:ticket_tier] do
        TicketTier.changeset(socket.assigns.ticket_tier, merged_params)
      else
        TicketTier.changeset(%TicketTier{}, merged_params)
      end
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", params, socket) do
    # Handle cases where params might not have the expected structure
    ticket_tier_params = params["ticket_tier"] || params

    ticket_tier_params =
      ticket_tier_params
      |> maybe_parse_price()
      |> maybe_set_free_price()
      |> maybe_set_unlimited_quantity()

    changeset =
      if socket.assigns[:ticket_tier] do
        TicketTier.changeset(socket.assigns.ticket_tier, ticket_tier_params)
      else
        TicketTier.changeset(%TicketTier{}, ticket_tier_params)
      end
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign_form(changeset)}
  end

  @impl true
  def handle_event("save", params, socket) do
    # Handle both expected and unexpected parameter formats
    ticket_tier_params = params["ticket_tier"] || params

    ticket_tier_params =
      ticket_tier_params
      |> maybe_parse_price()
      |> maybe_set_free_price()
      |> maybe_set_unlimited_quantity()
      |> Map.put("event_id", socket.assigns.event_id)

    result =
      if socket.assigns[:ticket_tier] do
        # Updating existing ticket tier
        Ysc.Events.update_ticket_tier(
          socket.assigns.ticket_tier,
          ticket_tier_params
        )
      else
        # Creating new ticket tier
        Ysc.Events.create_ticket_tier(ticket_tier_params)
      end

    case result do
      {:ok, _ticket_tier} ->
        # Reset the form and close modal
        changeset =
          TicketTier.changeset(%TicketTier{}, %{unlimited_quantity: false})

        action = if socket.assigns[:ticket_tier], do: "updated", else: "added"

        {:noreply,
         socket
         |> put_flash(:info, "Ticket tier #{action} successfully")
         |> assign_form(changeset)
         |> push_navigate(
           to: ~p"/admin/events/#{socket.assigns.event_id}/tickets"
         )}

      {:error, changeset} ->
        {:noreply, socket |> assign_form(changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "ticket_tier")

    # Only show errors if the changeset has been validated (has an action)
    check_errors = changeset.action == :validate
    assign(socket, form: form, check_errors: check_errors)
  end

  defp get_existing_form_values(form) do
    # Extract current values from the form/changeset
    # apply_changes merges the changeset's data and changes to get current state
    changeset = form.source

    # Get the current state of all fields from the changeset
    current_state = Ecto.Changeset.apply_changes(changeset)

    # Also get any pending changes that haven't been applied yet
    changes = changeset.changes

    # Merge current state with changes, preferring changes for user input
    merged_values =
      Map.merge(current_state, changes)
      |> Map.take([
        :name,
        :description,
        :type,
        :price,
        :quantity,
        :unlimited_quantity,
        :start_date,
        :end_date,
        :requires_registration,
        :event_id
      ])

    # Convert to string keys and format values, keeping all values including nil
    merged_values
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), format_form_value(v)}
      {k, v} -> {k, format_form_value(v)}
    end)
    |> Enum.into(%{})
  end

  defp format_form_value(%Money{} = money) do
    case Ysc.MoneyHelper.format_money(money) do
      {:ok, formatted} -> formatted
      _ -> nil
    end
  end

  defp format_form_value(%Date{} = date) do
    Date.to_iso8601(date)
  end

  defp format_form_value(%DateTime{} = dt) do
    DateTime.to_iso8601(dt)
  end

  defp format_form_value(%NaiveDateTime{} = dt) do
    NaiveDateTime.to_iso8601(dt)
  end

  defp format_form_value(value) when is_atom(value) do
    Atom.to_string(value)
  end

  defp format_form_value(value), do: value

  defp format_money(nil), do: nil
  defp format_money(""), do: nil

  defp format_money(%Money{} = value) do
    case Ysc.MoneyHelper.format_money(value) do
      {:ok, money} -> money
      _ -> nil
    end
  end

  defp sale_end_min_date(nil), do: Date.utc_today()
  defp sale_end_min_date(""), do: Date.utc_today()

  defp sale_end_min_date(start) do
    start
  end

  defp maybe_parse_price(params) do
    case params["price"] do
      nil -> params
      "" -> params
      price -> Map.put(params, "price", Ysc.MoneyHelper.parse_money(price))
    end
  end

  defp maybe_set_free_price(params) do
    case params["type"] do
      "free" -> Map.put(params, "price", Money.new(0, :USD))
      "donation" -> Map.put(params, "price", nil)
      _ -> params
    end
  end

  defp maybe_set_unlimited_quantity(params) do
    case params["unlimited_quantity"] do
      "true" ->
        params
        |> Map.put("quantity", nil)
        |> Map.put("unlimited_quantity", true)

      true ->
        params
        |> Map.put("quantity", nil)
        |> Map.put("unlimited_quantity", true)

      "false" ->
        params
        |> Map.put("unlimited_quantity", false)

      false ->
        params
        |> Map.put("unlimited_quantity", false)

      _ ->
        params
    end
  end

  defp paid_type?(nil), do: false
  defp paid_type?("paid"), do: true
  defp paid_type?(:paid), do: true
  defp paid_type?(_), do: false

  defp donation_type?(nil), do: false
  defp donation_type?("donation"), do: true
  defp donation_type?(:donation), do: true
  defp donation_type?(_), do: false
end
