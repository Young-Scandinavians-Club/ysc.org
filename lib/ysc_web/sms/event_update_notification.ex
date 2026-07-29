defmodule YscWeb.Sms.EventUpdateNotification do
  @moduledoc """
  SMS template for admin event update text blasts.

  Body is precomputed (HTML stripped + soft-capped) and passed as `:body`.
  """

  alias YscWeb.Sms.Template

  @doc """
  Gets the template name.
  """
  def get_template_name, do: "event_update_notification"

  @doc """
  Renders the SMS message body.
  """
  def render(variables) do
    body = Map.get(variables, :body) || Map.get(variables, "body") || ""

    body
    |> to_string()
    |> Template.normalize_body()
  end

  @doc """
  Prepares SMS template variables for an event update blast.
  """
  def prepare_sms_data(sms_body, first_name \\ nil) when is_binary(sms_body) do
    %{
      body: sms_body,
      first_name: first_name
    }
  end
end
