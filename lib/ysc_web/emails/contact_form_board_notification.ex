defmodule YscWeb.Emails.ContactFormBoardNotification do
  @moduledoc """
  Email template for contact form board notification.

  Notifies board members when a new contact form is submitted.
  """
  use MjmlEEx,
    mjml_template: "templates/contact_form_board_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [admin_dashboard_url: 0]

  def get_template_name() do
    "contact_form_board_notification"
  end

  def get_subject() do
    "New Contact Form Submission - YSC"
  end
end
