defmodule YscWeb.Emails.ApplicationSubmitted do
  @moduledoc """
  Email template for application submission confirmation.

  Sends a confirmation email to users after submitting their membership application.
  """
  use MjmlEEx,
    mjml_template: "templates/application_submitted.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  import YscWeb.Emails.Helpers, only: [news_url: 0, upcoming_events_url: 0]

  alias Ysc.Settings

  def get_template_name() do
    "application_submitted"
  end

  def get_subject() do
    "Your Young Scandinavians Club application is in! 🎉"
  end

  def latest_news_url(), do: news_url()

  def facebook_path() do
    Settings.get_social_url("facebook")
  end

  def instagram_path() do
    Settings.get_social_url("instagram")
  end
end
