defmodule YscWeb.Emails.VolunteerBoardNotification do
  @moduledoc """
  Email template for volunteer board notification.

  Notifies board members when a new volunteer application is submitted.
  """
  use MjmlEEx,
    mjml_template: "templates/volunteer_board_notification.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: []

  def get_template_name() do
    "volunteer_board_notification"
  end

  def get_subject() do
    "New Volunteer Signup - YSC Board Review"
  end

  def admin_dashboard_url(), do: YscWeb.Emails.Helpers.admin_dashboard_url()
end
