defmodule YscWeb.Emails.AdminMembershipReport do
  @moduledoc """
  Email template for membership activity report.

  Sent to the board when an admin generates and emails a membership report.
  """
  use MjmlEEx,
    mjml_template: "templates/admin_membership_report.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name, do: "admin_membership_report"
end
