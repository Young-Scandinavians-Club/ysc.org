defmodule YscWeb.FormHelpers do
  @moduledoc """
  Shared helpers for Phoenix form field errors.
  """

  @doc """
  Normalizes a changeset/form error tuple to its message string.
  """
  def format_form_error({_key, {msg, _type}}), do: msg
  def format_form_error({msg, _type}), do: msg
end
