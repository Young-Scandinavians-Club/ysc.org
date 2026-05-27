defmodule YscWeb.Emails.ApplicationSubmitted do
  @moduledoc """
  Email template for application submission confirmation.

  Sends a confirmation email to users after submitting their membership application.
  """
  use MjmlEEx,
    mjml_template: "templates/application_submitted.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: []

  alias Ysc.Settings

  def get_template_name() do
    "application_submitted"
  end

  def get_subject() do
    "Your Young Scandinavians Club application is in! 🎉"
  end

  def upcoming_events_url(), do: YscWeb.Emails.Helpers.upcoming_events_url()

  def latest_news_url(), do: YscWeb.Emails.Helpers.news_url()

  def facebook_path() do
    Settings.get_social_url("facebook")
  end

  def instagram_path() do
    Settings.get_social_url("instagram")
  end
end
