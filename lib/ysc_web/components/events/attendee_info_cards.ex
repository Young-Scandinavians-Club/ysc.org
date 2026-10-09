defmodule YscWeb.Components.Events.AttendeeInfoCards do
  @moduledoc """
  The per-ticket "who's going" cards shown during event checkout (paid and
  free flows).

  Each card adapts to what the ticket's tier asks for
  (`Ysc.Events.AttendeeInfo`):

    * a "Who is this ticket for?" picker (me / family member / someone else),
      shown when the tier collects a name and email or pre-fills a question
      from a date of birth
    * first name / last name / email inputs, when the tier collects identity
    * the tier's extra questions, one input per question

  Events pushed to the LiveView: `select-ticket-attendee`,
  `update-registration-field` and `update-attendee-answer`.
  """
  use Phoenix.Component

  import YscWeb.CoreComponents

  alias Ysc.Events.AttendeeInfo

  @input_class "mt-2 block w-full rounded-sm text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6 border-zinc-300 focus:border-zinc-400"

  @doc """
  Headline copy for the section, based on what the tickets ask for.
  """
  def heading(tickets) do
    if Enum.any?(tickets, &AttendeeInfo.ticket_collects_identity?/1),
      do: "Who's going?",
      else: "A few more details"
  end

  def intro(tickets) do
    cond do
      Enum.any?(tickets, &AttendeeInfo.ticket_collects_email?/1) ->
        "Add a name and email for each person attending."

      Enum.any?(tickets, &AttendeeInfo.ticket_collects_identity?/1) ->
        "Add a name for each person attending."

      true ->
        "Tell us a little more about each ticket."
    end
  end

  attr :tickets, :list, required: true, doc: "tickets whose tier asks for info"

  attr :state, :map,
    required: true,
    doc:
      "checkout assigns: :tickets_for_me, :selected_family_members, :family_members, :ticket_details_form, :current_user"

  def attendee_cards(assigns) do
    ~H"""
    <.attendee_card
      :for={{ticket, index} <- Enum.with_index(@tickets)}
      ticket={ticket}
      index={index}
      total={length(@tickets)}
      tickets={@tickets}
      state={@state}
    />
    """
  end

  attr :ticket, :map, required: true
  attr :index, :integer, required: true
  attr :total, :integer, required: true
  attr :tickets, :list, required: true
  attr :state, :map, required: true

  defp attendee_card(assigns) do
    ticket = assigns.ticket
    state = assigns.state
    tier = ticket.ticket_tier

    resolved = AttendeeInfo.resolve(ticket, state)
    identity? = AttendeeInfo.collects_identity?(tier)
    email? = AttendeeInfo.collects_email?(tier)
    questions = AttendeeInfo.questions(tier)

    tickets_for_me = state.tickets_for_me || %{}

    me_taken_elsewhere? =
      Enum.any?(assigns.tickets, fn other ->
        other.id != ticket.id and
          (Map.get(tickets_for_me, other.id, false) ||
             Map.get(tickets_for_me, to_string(other.id), false))
      end)

    assigns =
      assigns
      |> assign(:resolved, resolved)
      |> assign(:identity?, identity?)
      |> assign(:email?, email?)
      |> assign(:questions, questions)
      |> assign(:picker?, identity? or AttendeeInfo.prefills?(tier))
      |> assign(:complete?, AttendeeInfo.complete?(ticket, state))
      |> assign(:me_taken_elsewhere?, me_taken_elsewhere?)
      |> assign(
        :other_family_members,
        Enum.reject(
          state.family_members || [],
          &(&1.id == state.current_user.id)
        )
      )
      |> assign(:input_class, @input_class)

    ~H"""
    <div
      id={"attendee-card-#{@ticket.id}"}
      class={[
        "relative rounded-xl p-4 space-y-4 transition duration-200",
        if(@complete?,
          do: "border-2 border-green-500 bg-green-50/30",
          else: "border border-zinc-200"
        )
      ]}
    >
      <div :if={@complete?} class="absolute top-4 right-4">
        <.icon name="hero-check-circle" class="w-6 h-6 text-green-600" />
      </div>

      <div>
        <h4 class="text-base font-semibold text-zinc-900">
          Ticket {@index + 1} of {@total}
        </h4>
        <p class="text-xs text-zinc-600">{@ticket.ticket_tier.name}</p>
      </div>

      <form
        :if={@picker?}
        id={"ticket-#{@ticket.id}-attendee-form"}
        phx-change="select-ticket-attendee"
        phx-debounce="100"
      >
        <input type="hidden" name="ticket_id" value={to_string(@ticket.id)} />
        <div>
          <label
            for={"ticket_#{@ticket.id}_attendee_select"}
            class="block text-sm font-medium text-zinc-700 mb-2"
          >
            Who is this ticket for?
          </label>
          <select
            id={"ticket_#{@ticket.id}_attendee_select"}
            name={"ticket_#{@ticket.id}_attendee_select"}
            class="block w-full rounded-md border-zinc-300 py-2.5 pl-3 pr-10 text-sm focus:border-blue-500 focus:outline-hidden focus:ring-blue-500"
          >
            <option
              value="me"
              selected={@resolved.source == :me}
              disabled={@me_taken_elsewhere? and @resolved.source != :me}
            >
              Me ({@state.current_user.first_name || @state.current_user.email})
              <%= if @me_taken_elsewhere? and @resolved.source != :me do %>
                (Already selected for another ticket)
              <% end %>
            </option>
            <optgroup :if={@other_family_members != []} label="Family Members">
              <option
                :for={member <- @other_family_members}
                value={"family_#{member.id}"}
                selected={
                  @resolved.source == :family and @resolved.person.id == member.id
                }
              >
                {member.first_name} {member.last_name}
              </option>
            </optgroup>
            <option value="other" selected={@resolved.source == :other}>
              {if @identity?,
                do: "Someone else (Enter details)",
                else: "Someone else"}
            </option>
          </select>
        </div>
      </form>

      <%= if @identity? do %>
        <form
          id={"ticket-#{@ticket.id}-registration-form"}
          phx-change="update-registration-field"
          phx-debounce="500"
        >
          <div
            id={"ticket_#{@ticket.id}_registration_fields"}
            class={if(@resolved.source == :other, do: "block", else: "hidden")}
          >
            <div class="space-y-4">
              <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
                <div>
                  <label
                    for={"ticket_#{@ticket.id}_first_name"}
                    class="block text-sm font-medium text-zinc-700"
                  >
                    First Name
                  </label>
                  <input
                    type="text"
                    id={"ticket_#{@ticket.id}_first_name"}
                    name={"ticket_#{@ticket.id}_first_name"}
                    value={@resolved.identity.first_name}
                    required={@resolved.source == :other}
                    disabled={@resolved.source != :other}
                    phx-value-ticket-id={@ticket.id}
                    phx-value-field="first_name"
                    enterkeyhint="next"
                    class={@input_class}
                  />
                </div>
                <div>
                  <label
                    for={"ticket_#{@ticket.id}_last_name"}
                    class="block text-sm font-medium text-zinc-700"
                  >
                    Last Name
                  </label>
                  <input
                    type="text"
                    id={"ticket_#{@ticket.id}_last_name"}
                    name={"ticket_#{@ticket.id}_last_name"}
                    value={@resolved.identity.last_name}
                    required={@resolved.source == :other}
                    disabled={@resolved.source != :other}
                    phx-value-ticket-id={@ticket.id}
                    phx-value-field="last_name"
                    enterkeyhint="next"
                    class={@input_class}
                  />
                </div>
              </div>
              <div :if={@email?}>
                <label
                  for={"ticket_#{@ticket.id}_email"}
                  class="block text-sm font-medium text-zinc-700"
                >
                  Email
                </label>
                <input
                  type="email"
                  id={"ticket_#{@ticket.id}_email"}
                  name={"ticket_#{@ticket.id}_email"}
                  value={@resolved.identity.email}
                  required={@resolved.source == :other}
                  disabled={@resolved.source != :other}
                  autocomplete="email"
                  enterkeyhint="done"
                  phx-value-ticket-id={@ticket.id}
                  phx-value-field="email"
                  class={@input_class}
                />
              </div>
            </div>
          </div>
        </form>

        <div
          id={"ticket-#{@ticket.id}-identity-summary"}
          class={if(@resolved.source == :other, do: "hidden", else: "block")}
        >
          <div class="bg-blue-50 border border-blue-200 rounded-xl p-3">
            <p class="text-sm text-blue-800">
              <strong>
                {@resolved.identity.first_name} {@resolved.identity.last_name}
              </strong>
              <br :if={@email?} />
              <span :if={@email?} class="text-blue-600">
                {@resolved.identity.email}
              </span>
            </p>
          </div>
        </div>
      <% end %>

      <form
        :if={@questions != []}
        id={"ticket-#{@ticket.id}-answers-form"}
        phx-change="update-attendee-answer"
        class="space-y-4"
      >
        <.attendee_question
          :for={question <- @questions}
          ticket_id={@ticket.id}
          question={question}
          raw={Map.get(@resolved.answers, question.id, "")}
          input_class={@input_class}
        />
      </form>
    </div>
    """
  end

  attr :ticket_id, :any, required: true
  attr :question, :map, required: true
  attr :raw, :any, default: ""
  attr :input_class, :string, required: true

  defp attendee_question(assigns) do
    question = assigns.question
    raw = to_string(assigns.raw || "")

    error =
      if String.trim(raw) == "" do
        nil
      else
        case AttendeeInfo.cast_answers([question], %{question.id => raw}) do
          {:error, errors} -> Map.get(errors, question.id)
          _ -> nil
        end
      end

    assigns =
      assigns
      |> assign(:raw, raw)
      |> assign(:error, error)
      |> assign(:field_id, "ticket_#{assigns.ticket_id}_answer_#{question.id}")
      |> assign(
        :help_id,
        "ticket_#{assigns.ticket_id}_answer_#{question.id}_help"
      )

    ~H"""
    <div id={"#{@field_id}_wrapper"}>
      <%= if @question.type == :yes_no do %>
        <fieldset aria-describedby={@question.help_text && @help_id}>
          <legend class="block text-sm font-medium text-zinc-700">
            {@question.label}
            <span :if={@question.required} class="text-red-600">*</span>
            <span :if={!@question.required} class="font-normal text-zinc-400">
              (optional)
            </span>
          </legend>
          <p
            :if={@question.help_text}
            id={@help_id}
            class="text-xs text-zinc-500 mt-0.5"
          >
            {@question.help_text}
          </p>
          <div class="mt-2 flex items-center gap-6">
            <label
              :for={{value, text} <- [{"yes", "Yes"}, {"no", "No"}]}
              class="inline-flex items-center gap-2 text-sm text-zinc-700"
            >
              <input
                type="radio"
                id={"#{@field_id}_#{value}"}
                name={@field_id}
                value={value}
                checked={@raw == value}
                class="border-zinc-300 text-blue-600 focus:ring-0"
              />
              {text}
            </label>
          </div>
        </fieldset>
      <% else %>
        <label for={@field_id} class="block text-sm font-medium text-zinc-700">
          {@question.label}
          <span :if={@question.required} class="text-red-600">*</span>
          <span :if={!@question.required} class="font-normal text-zinc-400">
            (optional)
          </span>
        </label>
        <p
          :if={@question.help_text}
          id={@help_id}
          class="text-xs text-zinc-500 mt-0.5"
        >
          {@question.help_text}
        </p>
        <%= case @question.type do %>
          <% :number -> %>
            <input
              type="number"
              inputmode="numeric"
              step="1"
              id={@field_id}
              name={@field_id}
              value={@raw}
              min={@question.min}
              max={@question.max}
              required={@question.required}
              aria-describedby={@question.help_text && @help_id}
              phx-debounce="300"
              class={@input_class}
            />
          <% :select -> %>
            <select
              id={@field_id}
              name={@field_id}
              required={@question.required}
              aria-describedby={@question.help_text && @help_id}
              class={@input_class}
            >
              <option value="" selected={@raw == ""}>Choose one…</option>
              <option
                :for={option <- @question.options}
                value={option}
                selected={@raw == option}
              >
                {option}
              </option>
            </select>
          <% _text -> %>
            <input
              type="text"
              id={@field_id}
              name={@field_id}
              value={@raw}
              maxlength="500"
              required={@question.required}
              aria-describedby={@question.help_text && @help_id}
              phx-debounce="300"
              class={@input_class}
            />
        <% end %>
      <% end %>
      <p :if={@error} class="mt-1 text-xs text-red-600">{@error}</p>
    </div>
    """
  end
end
