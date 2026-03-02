defmodule YscWeb.Emails.ApplicationApproved do
  @moduledoc """
  Email template for application approval notification.

  Notifies users when their membership application has been approved.
  """
  use MjmlEEx,
    mjml_template: "templates/application_approved.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  @doc """
  Returns the template name used by the notifier.
  """
  def get_template_name() do
    "application_approved"
  end

  @doc """
  Default subject line for an approved application.

  Kept as a separate function from `default_subject/1` so existing
  callers that rely on a static subject continue to work.
  """
  def get_subject() do
    "Velkommen! You're officially a Young Scandinavian 🎉 (One more step!)"
  end

  @doc """
  Returns the default subject for an approval email, given a user.

  This currently mirrors `get_subject/0` but accepts the user so the
  caller can use a single API for building default email content.
  """
  def default_subject(_user) do
    get_subject()
  end

  @doc """
  Returns a default plain-text email body for an approved application.

  This is used to prefill the editable email body in the admin
  application review UI, and also serves as the fallback body for the
  text-only part of the email.
  """
  def default_body(_user, _application \\ nil) do
    """
    We have fantastic news! Your application to join the Young Scandinavians Club has been approved.

    To unlock full access to our vibrant community and all the exciting benefits that come with being a member, there's just one more step: completing your membership payment.
    """
    |> String.trim()
  end

  def upcoming_events_url() do
    YscWeb.Endpoint.url() <> "/events"
  end

  def pay_membership_url() do
    YscWeb.Endpoint.url() <> "/users/membership"
  end
end
