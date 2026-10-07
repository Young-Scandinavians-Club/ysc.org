defmodule Ysc.Events.AttendeeQuestion do
  @moduledoc """
  A question an admin attaches to a ticket tier. Every ticket bought from the
  tier is asked the question at checkout and the answer is stored on the
  ticket's `Ysc.Events.TicketDetail`.

  Questions are embedded in `ticket_tiers.attendee_questions`. Each has a
  stable `id` (used as the key of the stored answers), a `label`, optional
  `help_text`, an answer `type` and whether it is `required`.

  Types:

    * `:text`   - free text
    * `:number` - whole number, optionally bounded by `min` / `max`
    * `:yes_no` - a yes / no choice
    * `:select` - pick one of `options`

  A `:number` question may set `prefill: :age` to be pre-filled with the age
  (on the event date) of the member or family member the ticket is for, when
  their date of birth is known.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @types [:text, :number, :yes_no, :select]
  @prefills [:age]

  @primary_key {:id, :string, autogenerate: false}
  embedded_schema do
    field :label, :string
    field :help_text, :string
    field :type, Ecto.Enum, values: @types, default: :text
    field :required, :boolean, default: false
    field :options, {:array, :string}, default: []
    field :min, :integer
    field :max, :integer
    field :prefill, Ecto.Enum, values: @prefills

    # One option per line in the admin form; parsed into `options`.
    field :options_text, :string, virtual: true
  end

  def types, do: @types

  @doc """
  Presets offered in the admin UI as one-click starting points.
  """
  def presets do
    [
      %{
        key: "dietary",
        title: "Dietary restrictions",
        attrs: %{
          label: "Dietary restrictions",
          help_text:
            "Let us know about any allergies or dietary needs so we can plan the food.",
          type: :text,
          required: false
        }
      },
      %{
        key: "child_age",
        title: "Child's age",
        attrs: %{
          label: "Child's age",
          help_text:
            "We ask the age of minors so we can make sure suitable food options are available.",
          type: :number,
          required: false,
          min: 0,
          prefill: :age
        }
      }
    ]
  end

  @doc """
  Generates a short, URL/DOM-safe, unique-enough question id.
  """
  def generate_id do
    :crypto.strong_rand_bytes(5) |> Base.encode16(case: :lower)
  end

  def changeset(question, attrs) do
    question
    |> cast(attrs, [
      :id,
      :label,
      :help_text,
      :type,
      :required,
      :min,
      :max,
      :prefill,
      :options_text
    ])
    |> ensure_id()
    |> update_change(:label, &trim/1)
    |> update_change(:help_text, &blank_to_nil/1)
    |> validate_required([:label])
    |> validate_length(:label, max: 120)
    |> validate_length(:help_text, max: 500)
    |> apply_options_text()
    |> validate_by_type()
  end

  defp ensure_id(changeset) do
    case get_field(changeset, :id) do
      id when id in [nil, ""] -> put_change(changeset, :id, generate_id())
      _ -> changeset
    end
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  # `options_text` (textarea, one option per line) is the editing surface;
  # `options` is what is stored and rendered.
  defp apply_options_text(changeset) do
    case fetch_change(changeset, :options_text) do
      {:ok, text} when is_binary(text) ->
        options =
          text
          |> String.split(["\r\n", "\n"], trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.uniq()

        put_change(changeset, :options, options)

      _ ->
        changeset
    end
  end

  defp validate_by_type(changeset) do
    case get_field(changeset, :type) do
      :select ->
        changeset
        |> clear_number_settings()
        |> validate_select_options()

      :number ->
        changeset
        |> put_change(:options, [])
        |> validate_number_range()

      type when type in [:text, :yes_no] ->
        changeset
        |> put_change(:options, [])
        |> clear_number_settings()

      _ ->
        changeset
    end
  end

  defp clear_number_settings(changeset) do
    changeset
    |> put_change(:min, nil)
    |> put_change(:max, nil)
    |> put_change(:prefill, nil)
  end

  defp validate_select_options(changeset) do
    options = get_field(changeset, :options) || []

    cond do
      length(options) < 2 ->
        add_error(changeset, :options_text, "add at least two choices")

      Enum.any?(options, &(String.length(&1) > 120)) ->
        add_error(
          changeset,
          :options_text,
          "each choice must be 120 characters or fewer"
        )

      true ->
        changeset
    end
  end

  defp validate_number_range(changeset) do
    min = get_field(changeset, :min)
    max = get_field(changeset, :max)

    if is_integer(min) and is_integer(max) and min > max do
      add_error(changeset, :max, "must be at least the minimum")
    else
      changeset
    end
  end
end
