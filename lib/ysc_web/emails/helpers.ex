defmodule YscWeb.Emails.Helpers do
  @moduledoc """
  Shared helpers for MJML email modules: public URLs and salutation names.
  """

  @member_default "Valued Member"

  @doc """
  Returns the public site origin (`YscWeb.Endpoint.url/0`), with no trailing slash.
  """
  def origin, do: YscWeb.Endpoint.url()

  @doc """
  Builds an absolute URL for a path that starts with `/`.
  """
  def absolute_url("/" <> _rest = path), do: origin() <> path

  @doc """
  Returns a first name for member-facing greetings.

  Uses `#{@member_default}` when the name is nil, empty, or only whitespace.
  Accepts a raw name (`nil` or `String.t()`) or any map/struct with a `:first_name` field.
  """
  def member_greeting_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> @member_default
      trimmed -> trimmed
    end
  end

  def member_greeting_name(nil), do: @member_default

  def member_greeting_name(%{} = entity) do
    entity
    |> Map.get(:first_name)
    |> member_greeting_name()
  end

  def member_greeting_name(_), do: @member_default
end
