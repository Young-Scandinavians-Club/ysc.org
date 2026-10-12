defmodule YscWeb.AdminEventsLive.TicketTierForm do
  use YscWeb, :live_component

  import YscWeb.AdminComponents

  alias Phoenix.LiveView.JS
  alias Ysc.Events.AttendeeQuestion
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
        <h2 class="text-lg text-zinc-900 type-subhead">
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
        class="space-y-5"
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
            <%!--
            The focus ring is a neutral zinc, deliberately unlike the blue
            "selected" style: the modal focuses the first radio on open, and a
            blue focus ring there read as a second selected option. zinc-600
            keeps the ring above 3:1 contrast against the white ring offset.
            --%>
            <label
              :for={{value, title, description, icon} <- type_options()}
              class={[
                "flex cursor-pointer flex-col gap-1 rounded-lg border p-3 transition-colors",
                "focus-within:ring-2 focus-within:ring-zinc-600 focus-within:ring-offset-1",
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

        <.input
          type="textarea"
          label="Description"
          field={@form[:description]}
        />

        <div
          :if={donation_type?(@tier_type)}
          class="rounded-lg border border-zinc-200 bg-zinc-50 p-3 text-xs text-zinc-600"
        >
          Attendees choose how much to give. Donation tiers have no fixed price,
          capacity limit, or sale window — they stay open until the event starts.
        </div>

        <section
          :if={!donation_type?(@tier_type)}
          id="tier-availability"
          aria-labelledby="tier-availability-heading"
          class="space-y-4 border-t border-zinc-100 pt-5"
        >
          <h3
            id="tier-availability-heading"
            class="text-sm text-zinc-900 type-subhead"
          >
            Availability
          </h3>

          <div class="flex flex-wrap items-end gap-x-6 gap-y-2">
            <div :if={!@form[:unlimited_quantity].value} class="w-full sm:w-40">
              <.input type="number" label="Quantity" field={@form[:quantity]} />
            </div>
            <.input
              type="checkbox"
              label="Unlimited quantity"
              field={@form[:unlimited_quantity]}
              phx-change="toggle_quantity_limit"
              phx-target={@myself}
            />
          </div>

          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
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
          </div>
          <p class="text-xs text-zinc-500">
            Leave blank to start selling now. Sales close when the event starts.
          </p>

          <div>
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
                class="mt-1 rounded-sm border-zinc-300 text-zinc-900 focus:ring-0"
              />
              <span class="flex flex-col gap-0.5">
                <span class="font-medium text-zinc-900">Member-only tier</span>
                <span class="text-xs text-zinc-500">
                  Single members get 1 ticket per event (across all member-only
                  tiers). Family and Lifetime members have no limit. Everyone
                  else can't buy this tier.
                </span>
              </span>
            </label>
            <.error :for={
              msg <- Enum.map(@form[:member_only].errors, &translate_error(&1))
            }>
              {msg}
            </.error>
          </div>
        </section>

        <section
          :if={!donation_type?(@tier_type)}
          id="tier-checkout"
          aria-labelledby="tier-checkout-heading"
          class="space-y-3 border-t border-zinc-100 pt-5"
        >
          <h3
            id="tier-checkout-heading"
            class="text-sm text-zinc-900 type-subhead"
          >
            Checkout
          </h3>
          <.attendee_info_section
            form={@form}
            myself={@myself}
            copyable_tiers={@copyable_tiers}
          />
        </section>

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

  attr :form, :any, required: true
  attr :myself, :any, required: true
  attr :copyable_tiers, :list, default: []

  # "Attendee info": what we ask for every ticket bought from this tier. One
  # switch for names/emails plus a small builder for extra questions. Tucked
  # behind a toggle that starts open only when something is configured, so
  # admins who just want to sell tickets never have to read past it.
  defp attendee_info_section(assigns) do
    assigns =
      assigns
      |> assign(
        :missing_presets,
        missing_presets(assigns.form[:attendee_questions])
      )
      |> assign(:asks_child_age?, asks_child_age?(assigns.form))
      |> assign(:summary, attendee_summary(assigns.form))
      |> assign(:open?, attendee_info_configured?(assigns.form))

    ~H"""
    <div>
      <button
        type="button"
        id="attendee-info-toggle"
        aria-controls="attendee-info-section"
        aria-expanded={to_string(@open?)}
        phx-click={
          JS.toggle(to: "#attendee-info-section")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
          |> JS.toggle_class("rotate-180", to: "#attendee-info-chevron")
        }
        class="flex w-full items-center justify-between gap-3 rounded-lg border border-zinc-200 px-3 py-2.5 text-left hover:bg-zinc-50"
      >
        <span class="min-w-0">
          <span class="block text-sm font-medium text-zinc-900">
            Attendee info
          </span>
          <span
            id="attendee-info-summary"
            class="block truncate text-xs text-zinc-500"
          >
            {@summary}
          </span>
        </span>
        <.icon
          name="hero-chevron-down"
          id="attendee-info-chevron"
          class={[
            "w-4 h-4 shrink-0 text-zinc-500 transition-transform",
            @open? && "rotate-180"
          ]}
        />
      </button>

      <div
        id="attendee-info-section"
        class={["mt-4 space-y-4", !@open? && "hidden"]}
      >
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
            class="mt-1 rounded-sm border-zinc-300 text-zinc-900 focus:ring-0"
          />
          <span class="flex flex-col gap-0.5">
            <span class="font-medium text-zinc-900">
              Ask for each guest's name and email
            </span>
            <span class="text-xs text-zinc-500">
              Collects first name, last name, and email for every ticket, not
              just the buyer's.
            </span>
            <span
              :if={@asks_child_age?}
              id="attendee-info-name-only-hint"
              class="text-xs text-zinc-500"
            >
              This tier asks for a child's age, so it collects a name only, no email.
            </span>
          </span>
        </label>
        <.error :for={
          msg <-
            Enum.map(@form[:requires_registration].errors, &translate_error(&1))
        }>
          {msg}
        </.error>

        <div class="space-y-3 border-t border-zinc-100 pt-4">
          <div>
            <h4 class="text-sm text-zinc-900 type-subhead">Extra questions</h4>
            <p class="text-xs text-zinc-500">
              Asked once per ticket. Admins and check-in staff see the
              answers; buyers see their own on the order confirmation.
            </p>
          </div>

          <input type="hidden" name="ticket_tier[attendee_questions_drop][]" />

          <.inputs_for :let={qf} field={@form[:attendee_questions]}>
            <.attendee_question_card
              form={qf}
              save_attempted?={@form.source.action in [:insert, :update]}
            />
          </.inputs_for>

          <.error :for={
            msg <-
              Enum.map(@form[:attendee_questions].errors, &translate_error(&1))
          }>
            {msg}
          </.error>

          <div class="flex flex-wrap items-center gap-2">
            <button
              :for={preset <- @missing_presets}
              type="button"
              id={"add-question-#{preset.key}"}
              phx-click="add-question"
              phx-value-preset={preset.key}
              phx-target={@myself}
              class="inline-flex items-center gap-1 rounded-full border border-zinc-300 bg-white px-3 py-1 text-xs font-medium text-zinc-700 hover:bg-zinc-50"
            >
              <.icon name="hero-plus" class="w-3.5 h-3.5" /> {preset.title}
            </button>
            <button
              type="button"
              id="add-question-custom"
              phx-click="add-question"
              phx-value-preset="custom"
              phx-target={@myself}
              class="inline-flex items-center gap-1 rounded-full border border-zinc-300 bg-white px-3 py-1 text-xs font-medium text-zinc-700 hover:bg-zinc-50"
            >
              <.icon name="hero-plus" class="w-3.5 h-3.5" /> Custom question
            </button>
          </div>

          <div
            :if={@copyable_tiers != []}
            class="flex flex-wrap items-center gap-2"
          >
            <span class="text-xs text-zinc-500">Copy questions from</span>
            <button
              :for={tier <- @copyable_tiers}
              type="button"
              id={"copy-questions-#{tier.id}"}
              phx-click="copy-questions"
              phx-value-tier-id={tier.id}
              phx-target={@myself}
              class="inline-flex items-center gap-1 rounded-full border border-zinc-300 bg-white px-3 py-1 text-xs font-medium text-zinc-700 hover:bg-zinc-50"
            >
              <.icon name="hero-document-duplicate" class="w-3.5 h-3.5" />
              {tier.name}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # True when the tier already asks for anything at checkout.
  defp attendee_info_configured?(form) do
    Phoenix.HTML.Form.normalize_value(
      "checkbox",
      form[:requires_registration].value
    ) or
      attendee_labels(form) != []
  end

  defp asks_child_age?(form) do
    form.source
    |> Ecto.Changeset.get_field(:attendee_questions)
    |> List.wrap()
    |> Enum.any?(&(&1.prefill == :age))
  end

  defp attendee_labels(form) do
    form.source
    |> Ecto.Changeset.get_field(:attendee_questions)
    |> List.wrap()
    |> Enum.map(& &1.label)
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  # One line naming what is asked, shown on the collapsed toggle.
  defp attendee_summary(form) do
    identity =
      if Phoenix.HTML.Form.normalize_value(
           "checkbox",
           form[:requires_registration].value
         ),
         do: [if(asks_child_age?(form), do: "Name", else: "Name & email")],
         else: []

    case identity ++ attendee_labels(form) do
      [] -> "Nothing extra — just the buyer"
      parts -> Enum.join(parts, ", ")
    end
  end

  attr :form, :any, required: true
  attr :save_attempted?, :boolean, default: false

  defp attendee_question_card(assigns) do
    assigns = assign(assigns, :type, to_string(assigns.form[:type].value))

    ~H"""
    <div
      id={"attendee-question-#{@form.index}"}
      class="rounded-lg border border-zinc-200 bg-zinc-50/50 p-3 space-y-3"
    >
      <input
        type="hidden"
        name="ticket_tier[attendee_questions_sort][]"
        value={@form.index}
      />
      <div class="flex items-start gap-2">
        <div class="flex-1">
          <.input
            type="text"
            label="Question"
            field={@form[:label]}
            placeholder="e.g. Dietary restrictions"
            maxlength="120"
          />
        </div>
        <label
          class="mt-8 inline-flex cursor-pointer items-center gap-1 text-xs text-zinc-500 hover:text-red-600"
          title="Remove this question"
        >
          <input
            type="checkbox"
            name="ticket_tier[attendee_questions_drop][]"
            value={@form.index}
            class="hidden"
          />
          <.icon name="hero-trash" class="w-4 h-4" />
          <span class="sr-only">Remove question</span>
        </label>
      </div>

      <.input
        type="text"
        label="Help text (optional)"
        field={@form[:help_text]}
        placeholder="Shown under the question at checkout"
        maxlength="500"
      />

      <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <.input
          type="select"
          label="Answer type"
          field={@form[:type]}
          options={question_type_options()}
        />
        <div class="sm:pt-8">
          <.input type="checkbox" label="Required" field={@form[:required]} />
        </div>
      </div>

      <%!-- Errors are passed explicitly: an untouched textarea counts as unused,
           which would hide "add at least two choices" after a failed save. --%>
      <.input
        :if={@type == "select"}
        type="textarea"
        label="Choices (one per line)"
        id={@form[:options_text].id}
        name={@form[:options_text].name}
        value={options_text(@form)}
        errors={
          if(@save_attempted?,
            do: Enum.map(@form[:options_text].errors, &translate_error/1),
            else: []
          )
        }
        rows="4"
      />

      <div :if={@type == "number"} class="space-y-3">
        <div class="grid grid-cols-2 gap-3">
          <.input type="number" label="Minimum (optional)" field={@form[:min]} />
          <.input type="number" label="Maximum (optional)" field={@form[:max]} />
        </div>
        <.input
          type="select"
          label="Pre-fill"
          field={@form[:prefill]}
          prompt="Don't pre-fill"
          options={[{"Age on the event date, from the guest's birthdate", "age"}]}
        />
      </div>
    </div>
    """
  end

  defp question_type_options do
    [
      {"Text", "text"},
      {"Number", "number"},
      {"Yes / No", "yes_no"},
      {"Pick one from a list", "select"}
    ]
  end

  defp options_text(form) do
    case Ecto.Changeset.get_field(form.source, :options_text) do
      text when is_binary(text) ->
        text

      _ ->
        form.source
        |> Ecto.Changeset.get_field(:options)
        |> List.wrap()
        |> Enum.join("\n")
    end
  end

  # Presets whose label isn't already among the tier's questions.
  defp missing_presets(field) do
    labels =
      field.form.source
      |> Ecto.Changeset.get_field(:attendee_questions)
      |> List.wrap()
      |> MapSet.new(& &1.label)

    Enum.reject(
      AttendeeQuestion.presets(),
      &MapSet.member?(labels, &1.attrs.label)
    )
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
     |> assign_new(:admin_role, fn -> nil end)
     |> assign_copyable_tiers()
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

  # Other tiers of this event that already have questions, offered as a
  # one-click copy so the same questions aren't rebuilt for every tier.
  defp assign_copyable_tiers(socket) do
    current_id = socket.assigns[:ticket_tier] && socket.assigns.ticket_tier.id

    tiers =
      socket.assigns.event_id
      |> Ysc.Events.list_tiers_with_attendee_questions()
      |> Enum.reject(&(&1.id == current_id))

    assign(socket, :copyable_tiers, tiers)
  end

  @impl true
  def handle_event("add-question", %{"preset" => preset_key}, socket) do
    attrs =
      case Enum.find(AttendeeQuestion.presets(), &(&1.key == preset_key)) do
        %{attrs: attrs} -> attrs
        nil -> %{label: nil}
      end

    question =
      struct(
        AttendeeQuestion,
        Map.put(attrs, :id, AttendeeQuestion.generate_id())
      )

    {:noreply, append_questions(socket, [question])}
  end

  def handle_event("copy-questions", %{"tier-id" => tier_id}, socket) do
    case Enum.find(socket.assigns.copyable_tiers, &(&1.id == tier_id)) do
      nil ->
        {:noreply, socket}

      tier ->
        existing_labels =
          socket.assigns.form.source
          |> Ecto.Changeset.get_field(:attendee_questions)
          |> MapSet.new(& &1.label)

        copies =
          tier.attendee_questions
          |> Enum.reject(&MapSet.member?(existing_labels, &1.label))
          |> Enum.map(&%{&1 | id: AttendeeQuestion.generate_id()})

        {:noreply, append_questions(socket, copies)}
    end
  end

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
    if socket.assigns[:admin_role] != :admin do
      {:noreply,
       YscWeb.Flash.put_toast(
         socket,
         :error,
         "You do not have permission to perform this action.",
         title: "Ticket tier"
       )}
    else
      save_ticket_tier(params, socket)
    end
  end

  defp save_ticket_tier(params, socket) do
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

  defp append_questions(socket, questions) do
    changeset = socket.assigns.form.source
    existing = Ecto.Changeset.get_field(changeset, :attendee_questions)

    changeset =
      changeset
      |> Ecto.Changeset.put_embed(:attendee_questions, existing ++ questions)
      |> Map.put(:action, :validate)

    assign_form(socket, changeset)
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
