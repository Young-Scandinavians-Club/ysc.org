defmodule YscWeb.Sms.EventUpdateNotification do
  @moduledoc """
  SMS template for admin event update text blasts.

  Body is precomputed (HTML stripped + soft-capped) and passed as `:body`.
  """

  # Keys required in priv/dev/notification_preview_samples.exs (mix lint_notification_samples).
  @preview_keys [:body]

  def preview_keys, do: @preview_keys

  @doc """
  Gets the template name.
  """
  def get_template_name, do: "event_update_notification"

  @doc """
  Renders the SMS message body.

  The body is precomputed by `YscWeb.Sms.Segment` (including intentional
  newlines). Do not re-normalize whitespace here or segment counts diverge
  from the admin preview.
  """
  def render(variables) do
    body = Map.get(variables, :body) || Map.get(variables, "body") || ""
    to_string(body)
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
