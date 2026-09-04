defmodule YscWeb.Emails.ApplicationApproved do
  @moduledoc """
  Email template for application approval notification.

  Notifies users when their membership application has been approved.
  """
  use MjmlEEx,
    mjml_template: "templates/application_approved.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: []

  def get_template_name() do
    "application_approved"
  end

  def get_subject() do
    "Velkommen! (Welcome!) Pay your membership dues to join YSC"
  end

  def upcoming_events_url(), do: YscWeb.Emails.Helpers.upcoming_events_url()

  def pay_membership_url(), do: YscWeb.Emails.Helpers.membership_url()
end
