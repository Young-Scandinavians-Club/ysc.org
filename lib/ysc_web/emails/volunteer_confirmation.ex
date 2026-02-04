defmodule YscWeb.Emails.VolunteerConfirmation do
  @moduledoc """
  Email template for volunteer confirmation.

  Sends a confirmation email to users after submitting a volunteer application.
  """
  use MjmlEEx,
    mjml_template: "templates/volunteer_confirmation.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "volunteer_confirmation"
  end

  def get_subject() do
    "Thank You for Volunteering with YSC!"
  end

  def contact_url() do
    YscWeb.Endpoint.url() <> "/contact"
  end
end
