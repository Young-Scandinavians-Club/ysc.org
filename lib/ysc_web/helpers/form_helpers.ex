defmodule YscWeb.FormHelpers do
  @moduledoc """
  Shared helpers for Phoenix form field and changeset errors.
  """

  use Gettext, backend: YscWeb.Gettext

  @doc """
  Normalizes a changeset/form error tuple to its message string.
  """
  def format_form_error({_key, {msg, _type}}), do: msg
  def format_form_error({msg, _type}), do: msg

  @doc """
  Translates a changeset error tuple using Gettext (same rules as `CoreComponents.translate_error/1`).
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(YscWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(YscWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Returns a map of field names to translated error message lists for a changeset.
  """
  def changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
  end

  @doc """
  Formats changeset errors as a single human-readable string.

  ## Options

    * `:style` - `:grouped` (default) groups messages by field; `:flat` emits one
      `"field: message"` segment per error
    * `:separator` - joins segments (default `"; "` for grouped, `". "` for flat)
    * `:field_format` - `:raw` (default) or `:humanize` field names
    * `:message_separator` - joins multiple messages for one field (default `", "`)

  ## Examples

      iex> alias YscWeb.FormHelpers
      iex> changeset = Ecto.Changeset.add_error(%Ecto.Changeset{}, :email, "is invalid")
      iex> FormHelpers.format_changeset_errors(changeset)
      "email: is invalid"

      iex> FormHelpers.format_changeset_errors(changeset, style: :flat)
      "email: is invalid"
  """
  def format_changeset_errors(changeset, opts \\ []) do
    style = Keyword.get(opts, :style, :grouped)
    field_format = Keyword.get(opts, :field_format, :raw)
    message_separator = Keyword.get(opts, :message_separator, ", ")

    separator =
      Keyword.get_lazy(opts, :separator, fn ->
        if style == :flat, do: ". ", else: "; "
      end)

    errors = changeset_errors(changeset)

    case style do
      :flat ->
        errors
        |> Enum.flat_map(fn {field, messages} ->
          field_label = format_field_name(field, field_format)

          Enum.map(messages, fn message ->
            "#{field_label}: #{message}"
          end)
        end)
        |> Enum.join(separator)

      _ ->
        Enum.map_join(errors, separator, fn {field, messages} ->
          field_label = format_field_name(field, field_format)
          "#{field_label}: #{Enum.join(messages, message_separator)}"
        end)
    end
  end

  defp format_field_name(field, :humanize), do: Phoenix.Naming.humanize(field)
  defp format_field_name(field, _), do: to_string(field)
end
