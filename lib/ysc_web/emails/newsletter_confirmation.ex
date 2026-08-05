defmodule YscWeb.Emails.NewsletterConfirmation do
  @moduledoc """
  Double opt-in confirmation email for anonymous newsletter signups.

  Deliberately plain (no images, one button, no secondary links) — its only
  job is getting the confirmation link clicked. Used both for the initial
  send and, with `@reminder` set, for the 24-hour follow-up.
  """
  use MjmlEEx,
    mjml_template: "templates/newsletter_confirmation.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name() do
    "newsletter_confirmation"
  end
end
