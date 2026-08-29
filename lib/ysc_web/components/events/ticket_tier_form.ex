defmodule YscWeb.AdminEventsLive.TicketTierForm do
  use YscWeb, :live_component

  import YscWeb.AdminComponents

  alias Phoenix.LiveView.JS
  alias Ysc.Events.TicketTier

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:tier_type, to_string(assigns.form[:type].value))
      |> assign_new(:dialog_id, fn -> nil end)

    ~H"""
    <div id={"#{@event_id}-ticket-tier-form"}>
      <div class="mb-5">
        <h2 class="text-lg font-semibold text-zinc-900">
          {if assigns[:ticket_tier], do: "Edit ticket tier", else: "New ticket tier"}
        </h2>
        <p class="mt-0.5 text-sm text-zinc-500">
          Pick a tier type, then fill in what attendees see at checkout.
        </p>
      </div>

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

        <div>
          <span class="block text-sm font-semibold leading-6 text-zinc-700">
            Type
          </span>
          <div
            id="ticket-tier-type-options"
            class="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-3"
            role="radiogroup"
            aria-label="Ticket tier type"
          >
            <label
              :for={{value, title, description, icon} <- type_options()}
              class={[
                "flex cursor-pointer flex-col gap-1 rounded-lg border p-3 transition-colors",
                "focus-within:ring-2 focus-within:ring-blue-500 focus-within:ring-offset-1",
                if(@tier_type == value,
                  do: "border-blue-600 bg-blue-50 ring-1 ring-blue-600",
                  else: "border-zinc-200 hover:border-zinc-300 hover:bg-zinc-50"
                )
              ]}
            >
              <input
                type="radio"
                name={@form[:type].name}
                value={value}
                checked={@tier_type == value}
                class="sr-only"
                required
              />
              <span class="flex items-center gap-1.5 text-sm font-semibold text-zinc-800">
                <.icon name={icon} class="h-4 w-4 text-zinc-500" /> {title}
              </span>
              <span class="text-xs text-zinc-500">{description}</span>
            </label>
          </div>
          <.error :for={msg <- Enum.map(@form[:type].errors, &translate_error(&1))}>
            {msg}
          </.error>
        </div>

        <.input type="text" label="Name" field={@form[:name]} required />

        <.input
          type="textarea"
          label="Description"
          field={@form[:description]}
        />

        <.input
          :if={paid_type?(@tier_type)}
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

        <div
          :if={donation_type?(@tier_type)}
          class="rounded-lg border border-emerald-200 bg-emerald-50 p-3 text-xs text-emerald-800"
        >
          Attendees choose how much to give. Donation tiers have no fixed price,
          capacity limit, or sale window — they stay open until the event starts.
        </div>

        <div
          :if={!donation_type?(@tier_type)}
          class="space-y-4 border-t border-zinc-100 pt-4"
        >
          <.input
            type="checkbox"
            label="Unlimited quantity"
            field={@form[:unlimited_quantity]}
            phx-change="toggle_quantity_limit"
            phx-target={@myself}
          />

          <.input
            :if={!@form[:unlimited_quantity].value}
            type="number"
            label="Quantity"
            field={@form[:quantity]}
          />

          <.date_picker
            id="sales_start"
            label="Sale Starts"
            form={@form}
            start_date_field={@form[:start_date]}
            min={Date.utc_today()}
            required={false}
            timezone="America/Los_Angeles"
          />
          <.date_picker
            id="sale_ends"
            label="Sale Ends"
            form={@form}
            start_date_field={@form[:end_date]}
            min={sale_end_min_date(@form[:start_date].value)}
            required={false}
            timezone="America/Los_Angeles"
            end_of_day?={true}
          />
          <p class="text-xs text-zinc-500">
            Leave the sale dates blank to start selling right away. Sales always
            close once the event begins.
          </p>
        </div>

        <div
          :if={!donation_type?(@tier_type)}
          class="space-y-3 border-t border-zinc-100 pt-4"
        >
          <div class="rounded-lg border border-sky-200 bg-sky-50 p-3">
            <label class="flex items-start gap-3 text-sm leading-6 text-zinc-700">
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
                class="mt-1 rounded border-zinc-300 text-sky-700 focus:ring-0"
              />
              <span class="flex flex-col gap-0.5">
                <span class="flex items-center gap-2 font-medium text-sky-900">
                  <.icon name="hero-identification" class="w-4 h-4" />
                  Requires registration
                </span>
                <span class="text-xs text-sky-800">
                  Collect first name, last name, and email for every ticket at
                  checkout — not just the buyer. Use this when you need a full
                  attendee list.
                </span>
              </span>
            </label>
            <.error :for={
              msg <-
                Enum.map(
                  @form[:requires_registration].errors,
                  &translate_error(&1)
                )
            }>
              {msg}
            </.error>
          </div>

          <div class="rounded-lg border border-violet-200 bg-violet-50 p-3">
            <label class="flex items-start gap-3 text-sm leading-6 text-zinc-700">
              <input
                type="hidden"
                name={@form[:member_only].name}
                value="false"
              />
              <input
                type="checkbox"
                id={@form[:member_only].id}
                name={@form[:member_only].name}
                value="true"
                checked={
                  Phoenix.HTML.Form.normalize_value(
                    "checkbox",
                    @form[:member_only].value
                  )
                }
                class="mt-1 rounded border-zinc-300 text-violet-700 focus:ring-0"
              />
              <span class="flex flex-col gap-0.5">
                <span class="flex items-center gap-2 font-medium text-violet-900">
                  <.icon name="hero-lock-closed" class="w-4 h-4" /> Member-only tier
                </span>
                <span class="text-xs text-violet-800">
                  Single members can buy just one member-only ticket per event
                  (across all member-only tiers). Family and Lifetime members have
                  no limit. Everyone else must buy from the regular tiers.
                </span>
              </span>
            </label>
            <.error :for={
              msg <- Enum.map(@form[:member_only].errors, &translate_error(&1))
            }>
              {msg}
            </.error>
          </div>
        </div>

        <div class="flex justify-end gap-2 border-t border-zinc-100 pt-4">
          <.button
            :if={@dialog_id}
            type="button"
            variant="outline"
            color="zinc"
            phx-click={JS.exec("data-cancel", to: "##{@dialog_id}")}
          >
            Cancel
          </.button>
          <.button type="submit" phx-disable-with="Saving...">
            <%= if assigns[:ticket_tier] do %>
              <.icon name="hero-pencil" /> Update Ticket Tier
            <% else %>
              <.icon name="hero-plus" /> Add Ticket Tier
            <% end %>
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  # Segmented "Type" control: {value, title, description, icon}
  defp type_options do
    [
      {"free", "Free", "No charge to attend", "hero-ticket"},
      {"paid", "Paid", "One fixed ticket price", "hero-banknotes"},
      {"donation", "Donation", "Attendee picks the amount", "hero-gift"}
    ]
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
     |> assign_new(:dialog_id, fn -> nil end)
     |> assign_new(:retained_price, fn ->
       case assigns[:ticket_tier] do
         %{type: type, price: price} ->
           if paid_type?(type), do: format_money(price)

         _ ->
           nil
       end
     end)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("toggle_quantity_limit", params, socket) do
    # Handle both expected and unexpected parameter formats
    ticket_tier_params = params["ticket_tier"] || params

    # Merge with existing form values to preserve fields like name, type, etc.
    existing_values = get_existing_form_values(socket.assigns.form)
    retained_price = update_retained_price(socket, ticket_tier_params)

    merged_params =
      Map.merge(existing_values, ticket_tier_params)
      |> maybe_restore_retained_price(ticket_tier_params, retained_price)
      |> maybe_parse_price()
      |> maybe_set_free_price()
      |> maybe_clear_donation_fields()
      |> maybe_set_unlimited_quantity()

    changeset =
      if socket.assigns[:ticket_tier] do
        TicketTier.changeset(socket.assigns.ticket_tier, merged_params)
      else
        TicketTier.changeset(%TicketTier{}, merged_params)
      end
      |> Map.put(:action, :validate)

    {:noreply,
     socket |> assign(:retained_price, retained_price) |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", params, socket) do
    # Handle cases where params might not have the expected structure
    ticket_tier_params = params["ticket_tier"] || params

    # Merge with existing form values to preserve fields that may be missing from params
    # (e.g. price when conditionally rendered, or when type changes before price is entered)
    existing_values =
      if socket.assigns[:form] do
        get_existing_form_values(socket.assigns.form)
      else
        %{}
      end

    retained_price = update_retained_price(socket, ticket_tier_params)

    merged_params =
      Map.merge(existing_values, ticket_tier_params)
      # Preserve price when params has empty price but form had valid price (e.g. quantity
      # change triggers phx-change; price input may not submit its value in some cases)
      |> preserve_price_if_empty(existing_values)
      # Bring back a price the user entered earlier when they switch Type away
      # from and back to a paid tier (the price input is hidden meanwhile).
      |> maybe_restore_retained_price(ticket_tier_params, retained_price)
      |> maybe_parse_price()
      |> maybe_set_free_price()
      |> maybe_clear_donation_fields()
      |> maybe_set_unlimited_quantity()

    changeset =
      if socket.assigns[:ticket_tier] do
        TicketTier.changeset(socket.assigns.ticket_tier, merged_params)
      else
        TicketTier.changeset(%TicketTier{}, merged_params)
      end
      |> Map.put(:action, :validate)

    {:noreply,
     socket |> assign(:retained_price, retained_price) |> assign_form(changeset)}
  end

  @impl true
  def handle_event("save", params, socket) do
    # Handle both expected and unexpected parameter formats
    ticket_tier_params = params["ticket_tier"] || params

    ticket_tier_params =
      ticket_tier_params
      |> maybe_parse_price()
      |> maybe_set_free_price()
      |> maybe_clear_donation_fields()
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
         |> YscWeb.Flash.put_toast(:info, "Ticket tier #{action} successfully",
           title: "Ticket tier"
         )
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
        :member_only,
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

  # nil must come before is_atom - prevents storing literal "nil" string for empty fields
  defp format_form_value(nil), do: ""

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

  # When incoming params have empty price but form had valid price (e.g. user changed
  # quantity and price input didn't submit), preserve the existing price for paid tiers.
  defp preserve_price_if_empty(merged_params, existing_values) do
    incoming_price = merged_params["price"]
    existing_price = existing_values["price"]
    type = merged_params["type"]

    price_is_empty =
      incoming_price in [nil, ""] or
        (is_binary(incoming_price) and String.trim(incoming_price) == "")

    existing_has_valid_price =
      existing_price != nil &&
        existing_price != "" &&
        (is_binary(existing_price) && String.trim(existing_price) != "")

    if price_is_empty and existing_has_valid_price and paid_type?(type) do
      Map.put(merged_params, "price", existing_price)
    else
      merged_params
    end
  end

  # Remember the last non-blank price the user typed, so it survives a detour
  # through the Free/Donation tier types (where the price input is not rendered).
  defp update_retained_price(socket, params) do
    current = socket.assigns[:retained_price]

    case params["price"] do
      price when is_binary(price) ->
        if String.trim(price) in ["", "$"], do: current, else: price

      _ ->
        current
    end
  end

  # When the incoming change payload carries no price key (the field was hidden
  # because Type was Free/Donation) and we're now on a paid tier, restore the
  # remembered price instead of falling back to the zeroed changeset value.
  defp maybe_restore_retained_price(params, _raw_params, nil), do: params

  defp maybe_restore_retained_price(params, raw_params, retained) do
    if paid_type?(params["type"]) and not Map.has_key?(raw_params, "price") do
      Map.put(params, "price", retained)
    else
      params
    end
  end

  defp maybe_parse_price(params) do
    case params["price"] do
      nil ->
        params

      "" ->
        params

      price when is_binary(price) ->
        if String.trim(price) == "" do
          params
        else
          Map.put(params, "price", Ysc.MoneyHelper.parse_money(price))
        end

      price ->
        Map.put(params, "price", Ysc.MoneyHelper.parse_money(price))
    end
  end

  defp maybe_set_free_price(params) do
    case params["type"] do
      "free" -> Map.put(params, "price", Money.new(0, :USD))
      "donation" -> Map.put(params, "price", nil)
      _ -> params
    end
  end

  # Donation tiers have no capacity limit or sale window. Clear those fields so
  # switching an existing limited/scheduled tier to Donation doesn't silently
  # keep its old quantity and sale dates after saving.
  defp maybe_clear_donation_fields(params) do
    if donation_type?(params["type"]) do
      params
      |> Map.put("quantity", nil)
      |> Map.put("start_date", nil)
      |> Map.put("end_date", nil)
    else
      params
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
