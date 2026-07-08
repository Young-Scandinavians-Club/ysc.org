defmodule YscWeb.Emails.NewSignInDetected do
  @moduledoc """
  Email template for unfamiliar sign-in notification.

  Alerts users when a sign-in happens from a new device or browser.
  """
  use MjmlEEx,
    mjml_template: "templates/new_sign_in_detected.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  alias Ysc.Accounts.AuthService
  alias YscWeb.Emails.Helpers, as: EmailHelpers

  def get_template_name() do
    "new_sign_in_detected"
  end

  @doc """
  Builds render assigns at send time so location can include async geo enrichment.
  """
  def prepare_email_data(user, auth_event_id) do
    case AuthService.fetch_auth_event_for_email(user.id, auth_event_id) do
      {:ok, auth_event} ->
        auth_event = AuthService.enrich_auth_event_geo(auth_event)
        {:ok, build_assigns(user, auth_event)}

      {:error, :not_found} ->
        {:error, :auth_event_not_found}
    end
  end

  @doc """
  Plain-text body for the unfamiliar sign-in notification.
  """
  def text_body(%{
        first_name: first_name,
        intro_text: intro_text,
        signed_in_at: signed_in_at,
        device: device,
        location: location,
        security_url: security_url
      }) do
    """
    ==============================

    Hi #{first_name},

    #{intro_text}

    Platform: #{device}
    Location: #{location}
    Time: #{signed_in_at}

    Go to your security settings for a list of your recent sign-ins and active sessions:
    #{security_url}

    If you didn't sign in or don't recognize this activity, sign out unfamiliar sessions from your security settings and contact us at info@ysc.org.

    ==============================
    """
  end

  defp build_assigns(user, auth_event) do
    %{
      first_name: Ysc.title_case(user.first_name),
      intro_text: intro_text(auth_event),
      signed_in_at: EmailHelpers.format_datetime(auth_event.inserted_at),
      device: EmailHelpers.sign_in_device_description(auth_event),
      location: EmailHelpers.sign_in_location(auth_event),
      security_url: EmailHelpers.security_settings_url()
    }
  end

  defp intro_text(%{threat_indicators: indicators}) when is_list(indicators) do
    new_device? = "new_device" in indicators
    unusual_location? = "unusual_location" in indicators

    cond do
      new_device? and unusual_location? ->
        "We noticed a sign-in to Young Scandinavians Club from a new device or location."

      new_device? ->
        "We noticed a sign-in to Young Scandinavians Club from a new device or browser."

      unusual_location? ->
        "We noticed a sign-in to Young Scandinavians Club from a new location."

      true ->
        "We noticed a sign-in to Young Scandinavians Club."
    end
  end

  defp intro_text(_auth_event) do
    "We noticed a sign-in to Young Scandinavians Club."
  end
end
