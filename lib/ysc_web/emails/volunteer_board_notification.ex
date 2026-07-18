defmodule YscWeb.Emails.VolunteerBoardNotification do
  @moduledoc """
  Email template for volunteer board notification.

  Notifies board members when a new volunteer application is submitted.
  """
  use MjmlEEx,
    mjml_template: "templates/volunteer_board_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [admin_dashboard_url: 0]

  def get_template_name() do
    "volunteer_board_notification"
  end

  def get_subject() do
    "New Volunteer Signup - YSC Board Review"
  end
end
