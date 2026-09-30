defmodule Ysc.Events.AttendeeInfo do
  @moduledoc """
  What we ask about each ticket holder when a ticket is bought, and what we
  do with the answers.

  A ticket tier can collect two kinds of information per ticket:

    * **identity** - the attendee's first name, last name and email, switched
      on by `TicketTier.requires_registration`
    * **questions** - admin-defined `Ysc.Events.AttendeeQuestion`s stored on
      the tier (dietary restrictions, a child's age, ...)

  Either, both, or neither may be enabled. This module holds the pure logic
  shared by checkout, the member's ticket pages, the admin ticket list, the CSV
  export and the check-in screens: which tickets need information, how raw form
  input becomes stored answers, how answers are displayed, and how answers are
  pre-filled from a person's date of birth.

  ## Stored answers

  Answers live on `TicketDetail.answers` as a map keyed by question id:

      %{"a1b2c3d4e5" => %{"label" => "Dietary restrictions", "type" => "text",
                          "position" => 0, "value" => "Vegetarian"}}

  The label/type/position are a snapshot taken when the answer was given, so
  editing or deleting a question later never rewrites history.
  """

  alias Ysc.Events.AttendeeQuestion

  @max_text_length 500

  # ---------------------------------------------------------------------------
  # What a tier asks
  # ---------------------------------------------------------------------------

  @doc "The questions configured on a tier (`[]` for donations or nil)."
  def questions(%{type: :donation}), do: []
  def questions(%{attendee_questions: qs}) when is_list(qs), do: qs
  def questions(_), do: []

  @doc "Whether tickets of this tier need an attendee name and email."
  def collects_identity?(%{type: :donation}), do: false
  def collects_identity?(%{requires_registration: true}), do: true
  def collects_identity?(_), do: false

  @doc "Whether tickets of this tier need anything from the buyer beyond payment."
  def collects_info?(tier),
    do: collects_identity?(tier) or questions(tier) != []

  @doc "Whether any of the tier's questions pre-fills from a date of birth."
  def prefills?(tier), do: Enum.any?(questions(tier), &(&1.prefill == :age))

  @doc "Tickets (with `ticket_tier` loaded) whose tier asks for attendee info."
  def tickets_needing_info(tickets) do
    Enum.filter(tickets, fn ticket ->
      ticket.ticket_tier != nil and collects_info?(ticket.ticket_tier)
    end)
  end

  @doc "Whether the ticket's tier asks for an attendee name and email."
  def ticket_collects_identity?(%{ticket_tier: tier}),
    do: collects_identity?(tier)

  @doc "The questions asked for this ticket."
  def ticket_questions(%{ticket_tier: tier}), do: questions(tier)

  # ---------------------------------------------------------------------------
  # Turning raw form input into stored answers
  # ---------------------------------------------------------------------------

  @doc """
  Validates raw form input (`%{question_id => string}`) against a tier's
  questions.

  Returns `{:ok, answers}` where `answers` is the map to store (blank optional
  questions are left out), or `{:error, errors}` with `%{question_id =>
  message}` for every question that failed.
  """
  def cast_answers(questions, raw) when is_list(questions) do
    raw = raw || %{}

    {answers, errors} =
      questions
      |> Enum.with_index()
      |> Enum.reduce({%{}, %{}}, fn {question, position}, {answers, errors} ->
        case cast_answer(question, Map.get(raw, question.id)) do
          :skip ->
            {answers, errors}

          {:ok, value} ->
            entry = %{
              "label" => question.label,
              "type" => Atom.to_string(question.type),
              "position" => position,
              "value" => value
            }

            {Map.put(answers, question.id, entry), errors}

          {:error, message} ->
            {answers, Map.put(errors, question.id, message)}
        end
      end)

    if errors == %{}, do: {:ok, answers}, else: {:error, errors}
  end

  defp cast_answer(question, raw) do
    case normalize_raw(raw) do
      nil ->
        if question.required, do: {:error, "is required"}, else: :skip

      value ->
        cast_value(question, value)
    end
  end

  defp normalize_raw(nil), do: nil

  defp normalize_raw(raw) when is_binary(raw) do
    case String.trim(raw) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_raw(raw) when is_integer(raw), do: Integer.to_string(raw)
  defp normalize_raw(true), do: "yes"
  defp normalize_raw(false), do: "no"
  defp normalize_raw(_), do: nil

  defp cast_value(%{type: :text}, value) do
    if String.length(value) > @max_text_length do
      {:error, "must be #{@max_text_length} characters or fewer"}
    else
      {:ok, value}
    end
  end

  defp cast_value(%{type: :number} = question, value) do
    case Integer.parse(value) do
      {number, ""} -> check_range(question, number)
      _ -> {:error, "must be a whole number"}
    end
  end

  defp cast_value(%{type: :yes_no}, value) do
    case String.downcase(value) do
      "yes" -> {:ok, true}
      "no" -> {:ok, false}
      _ -> {:error, "choose yes or no"}
    end
  end

  defp cast_value(%{type: :select, options: options}, value) do
    if value in (options || []),
      do: {:ok, value},
      else: {:error, "choose one of the options"}
  end

  defp check_range(%{min: min}, number) when is_integer(min) and number < min,
    do: {:error, "must be at least #{min}"}

  defp check_range(%{max: max}, number) when is_integer(max) and number > max,
    do: {:error, "must be at most #{max}"}

  defp check_range(_question, number), do: {:ok, number}

  @doc """
  Whether the raw form input is a valid answer set for the questions.
  """
  def valid_answers?(questions, raw),
    do: match?({:ok, _}, cast_answers(questions, raw))

  @doc """
  Turns stored answers back into raw form input (`%{question_id => string}`),
  for re-populating a form.
  """
  def answers_to_form(answers) when is_map(answers) do
    Map.new(answers, fn {id, entry} -> {id, form_value(entry)} end)
  end

  def answers_to_form(_), do: %{}

  defp form_value(%{"value" => true}), do: "yes"
  defp form_value(%{"value" => false}), do: "no"

  defp form_value(%{"value" => value}) when is_integer(value),
    do: Integer.to_string(value)

  defp form_value(%{"value" => value}) when is_binary(value), do: value
  defp form_value(_), do: ""

  # ---------------------------------------------------------------------------
  # Displaying answers
  # ---------------------------------------------------------------------------

  @doc """
  The answers of a ticket detail (or a bare answers map) as `[%{label:,
  value:}]` in the order the questions were asked. Unanswered questions are
  not listed.
  """
  def display_answers(%{answers: answers}), do: display_answers(answers)

  def display_answers(answers) when is_map(answers) do
    answers
    |> Map.values()
    |> Enum.sort_by(&Map.get(&1, "position", 0))
    |> Enum.map(fn entry ->
      %{label: Map.get(entry, "label", ""), value: display_value(entry)}
    end)
    |> Enum.reject(&(&1.value == ""))
  end

  def display_answers(_), do: []

  @doc "Human-readable value of a single stored answer."
  def display_value(%{"value" => true}), do: "Yes"
  def display_value(%{"value" => false}), do: "No"

  def display_value(%{"value" => value}) when is_integer(value),
    do: Integer.to_string(value)

  def display_value(%{"value" => value}) when is_binary(value), do: value
  def display_value(_), do: ""

  @doc "Whether a ticket detail has any answers."
  def answered?(%{answers: answers}) when is_map(answers),
    do: map_size(answers) > 0

  def answered?(_), do: false

  # ---------------------------------------------------------------------------
  # CSV export
  # ---------------------------------------------------------------------------

  @doc """
  Column headers for an export: every question the tiers currently ask, plus
  any label found in the stored answers (questions since removed or renamed).

  Questions are grouped by label, so "Dietary restrictions" asked by several
  tiers becomes one column. Columns keep the order questions are asked in.
  """
  def export_columns(tiers, details) do
    configured =
      Enum.flat_map(tiers, fn tier ->
        tier
        |> questions()
        |> Enum.with_index()
        |> Enum.map(fn {question, position} -> {question.label, position} end)
      end)

    answered =
      details
      |> Enum.flat_map(fn
        %{answers: answers} when is_map(answers) -> Map.values(answers)
        _ -> []
      end)
      |> Enum.map(fn entry ->
        {Map.get(entry, "label", ""), Map.get(entry, "position", 0)}
      end)

    (configured ++ answered)
    |> Enum.reject(fn {label, _position} -> label in [nil, ""] end)
    |> Enum.reduce(%{}, fn {label, position}, acc ->
      Map.update(acc, label, position, &min(&1, position))
    end)
    |> Enum.sort_by(fn {label, position} -> {position, label} end)
    |> Enum.map(fn {label, _position} -> label end)
  end

  @doc """
  The value of the answer with the given label for one ticket detail, as
  export text (`""` when unanswered).
  """
  def export_value(detail, label) do
    with %{answers: answers} when is_map(answers) <- detail,
         entry when not is_nil(entry) <-
           Enum.find(Map.values(answers), &(Map.get(&1, "label") == label)) do
      display_value(entry)
    else
      _ -> ""
    end
  end

  # ---------------------------------------------------------------------------
  # Pre-filling from a date of birth
  # ---------------------------------------------------------------------------

  @doc """
  Completed years between `dob` and `on_date`, or nil when the date of birth
  is unknown or after `on_date`.
  """
  def age_on(%Date{} = dob, %Date{} = on_date) do
    if Date.compare(dob, on_date) == :gt do
      nil
    else
      years = on_date.year - dob.year

      if {on_date.month, on_date.day} < {dob.month, dob.day},
        do: years - 1,
        else: years
    end
  end

  def age_on(_dob, _on_date), do: nil

  @doc """
  The calendar day of the event, used as the reference date for ages.
  """
  def event_date(%{start_date: %DateTime{} = dt}), do: DateTime.to_date(dt)
  def event_date(%{start_date: %Date{} = date}), do: date
  def event_date(_event), do: Date.utc_today()

  @doc """
  Sets every pre-filling question to the age of `person` on `on_date`.

  Called when someone picks who a ticket is for. Questions are cleared (`""`)
  when there's no person or no date of birth, so a previous person's age never
  lingers. Answers to other questions are untouched. `person` is anything with
  a `date_of_birth`, typically a `Ysc.Accounts.User`.
  """
  def apply_prefill(raw_answers, questions, person, on_date) do
    age =
      case person do
        %{date_of_birth: dob} -> age_on(dob, on_date)
        _ -> nil
      end

    questions
    |> Enum.filter(&(&1.prefill == :age))
    |> Enum.reduce(raw_answers || %{}, fn %AttendeeQuestion{id: id}, acc ->
      Map.put(acc, id, if(age, do: Integer.to_string(age), else: ""))
    end)
  end

  # ---------------------------------------------------------------------------
  # Checkout: who is a ticket for, and is its information complete?
  # ---------------------------------------------------------------------------

  @doc """
  Resolves who a ticket in checkout is for.

  `state` is a map with `:tickets_for_me`, `:selected_family_members`,
  `:family_members`, `:ticket_details_form` and `:current_user` (the checkout
  LiveView's assigns). Returns:

      %{source: :me | :family | :other,
        person: %User{} | nil,
        identity: %{first_name:, last_name:, email:},
        answers: %{question_id => raw string}}
  """
  def resolve(ticket, state) do
    ticket_id_str = to_string(ticket.id)
    tickets_for_me = state[:tickets_for_me] || %{}
    selected_family_members = state[:selected_family_members] || %{}
    family_members = state[:family_members] || []
    form = state[:ticket_details_form] || %{}

    form_map = Map.get(form, ticket_id_str) || Map.get(form, ticket.id) || %{}
    answers = get_in_form(form_map, :answers) || %{}

    for_me? =
      Map.get(tickets_for_me, ticket.id, false) ||
        Map.get(tickets_for_me, ticket_id_str, false)

    family_member_id =
      Map.get(selected_family_members, ticket.id) ||
        Map.get(selected_family_members, ticket_id_str)

    family_member =
      family_member_id &&
        Enum.find(
          family_members,
          &(to_string(&1.id) == to_string(family_member_id))
        )

    cond do
      for_me? ->
        user = state[:current_user]

        %{
          source: :me,
          person: user,
          identity: user_identity(user),
          answers: answers
        }

      family_member ->
        %{
          source: :family,
          person: family_member,
          identity: user_identity(family_member),
          answers: answers
        }

      true ->
        %{
          source: :other,
          person: nil,
          identity: %{
            first_name: get_in_form(form_map, :first_name) || "",
            last_name: get_in_form(form_map, :last_name) || "",
            email: get_in_form(form_map, :email) || ""
          },
          answers: answers
        }
    end
  end

  defp user_identity(user) do
    %{
      first_name: (user && user.first_name) || "",
      last_name: (user && user.last_name) || "",
      email: (user && user.email) || ""
    }
  end

  defp get_in_form(map, key),
    do: Map.get(map, key) || Map.get(map, to_string(key))

  @doc "Whether an identity has a name and a plausible email."
  def identity_complete?(%{first_name: first, last_name: last, email: email}) do
    present?(first) and present?(last) and present?(email) and
      String.contains?(email, "@")
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  @doc """
  Whether everything the ticket's tier asks for has been provided in checkout.
  """
  def complete?(ticket, state) do
    resolved = resolve(ticket, state)

    (not ticket_collects_identity?(ticket) or
       identity_complete?(resolved.identity)) and
      valid_answers?(ticket_questions(ticket), resolved.answers)
  end

  @doc "Whether every listed ticket has everything its tier asks for."
  def all_complete?(tickets, state),
    do: Enum.all?(tickets, &complete?(&1, state))

  @doc """
  Builds the attrs to persist for a ticket at the end of checkout, or
  `{:error, reason}` when what was entered is incomplete or invalid.

  The returned map is accepted by `Ysc.Events.create_ticket_details/1`.
  """
  def build_detail(ticket, state) do
    resolved = resolve(ticket, state)
    identity? = ticket_collects_identity?(ticket)

    with :ok <- check_identity(identity?, resolved.identity),
         {:ok, answers} <-
           cast_answers(ticket_questions(ticket), resolved.answers) do
      base = %{ticket_id: ticket.id, answers: answers, identity: identity?}

      if identity? do
        {:ok, Map.merge(base, resolved.identity)}
      else
        {:ok, base}
      end
    end
  end

  defp check_identity(false, _identity), do: :ok

  defp check_identity(true, identity) do
    if identity_complete?(identity), do: :ok, else: {:error, :identity}
  end
end
