defmodule YscWeb.Emails.ApplicationApprovedFamilyLinked do
  @moduledoc """
  Email template for application approval when linked to a family membership.

  Notifies users that their membership is immediately active (no payment needed).
  """
  use MjmlEEx,
    mjml_template: "templates/application_approved_family_linked.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: []

  def get_template_name do
    "application_approved_family_linked"
  end

  def get_subject do
    "Velkommen! You're officially a Young Scandinavian 🎉"
  end

  def upcoming_events_url, do: YscWeb.Emails.Helpers.upcoming_events_url()

  def home_url, do: YscWeb.Emails.Helpers.home_url()
end
