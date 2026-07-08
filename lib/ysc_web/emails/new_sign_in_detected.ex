defmodule YscWeb.Emails.NewSignInDetected do
  @moduledoc """
  Email template for unfamiliar login notification.

  Alerts users when a login happens from a new device or browser.
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
    {:ok, auth_event} = AuthService.fetch_auth_event_for_email(auth_event_id)
    auth_event = AuthService.enrich_auth_event_geo(auth_event)

    %{
      first_name: Ysc.title_case(user.first_name),
      signed_in_at: EmailHelpers.format_datetime(auth_event.inserted_at),
      device: EmailHelpers.sign_in_device_description(auth_event),
      location: EmailHelpers.sign_in_location(auth_event),
      security_url: EmailHelpers.security_settings_url()
    }
  end

  @doc """
  Plain-text body for the unfamiliar login notification.
  """
  def text_body(%{
        first_name: first_name,
        signed_in_at: signed_in_at,
        device: device,
        location: location,
        security_url: security_url
      }) do
    """
    ==============================

    Hi #{first_name},

    We noticed a login to Young Scandinavians Club from a new device or browser.

    Platform: #{device}
    Location: #{location}
    Time: #{signed_in_at}

    Go to your security settings for a list of your recent sign-ins and active sessions:
    #{security_url}

    If you didn't make this login or don't recognize this activity, sign out unfamiliar sessions from your security settings and contact us at info@ysc.org.

    ==============================
    """
  end
end
