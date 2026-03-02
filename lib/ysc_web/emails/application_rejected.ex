defmodule YscWeb.Emails.ApplicationRejected do
  @moduledoc """
  Email template for application rejection notification.

  Notifies users when their membership application has been rejected.
  """
  use MjmlEEx,
    mjml_template: "templates/application_rejected.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  @doc """
  Returns the template name used by the notifier.
  """
  def get_template_name() do
    "application_rejected"
  end

  @doc """
  Default subject line for a rejected application.

  Kept as a separate function from `default_subject/1` so existing
  callers that rely on a static subject continue to work.
  """
  def get_subject() do
    "Update on your Young Scandinavians Club application"
  end

  @doc """
  Returns the default subject for a rejection email, given a user.

  This currently mirrors `get_subject/0` but accepts the user so the
  caller can use a single API for building default email content.
  """
  def default_subject(_user) do
    get_subject()
  end

  @doc """
  Returns a default plain-text email body for a rejected application.

  This is used to prefill the editable email body in the admin
  application review UI. Includes the full template with eligibility
  criteria from the bylaws so admins can see, reference, and highlight
  them as needed.
  """
  def default_body(_user, _application \\ nil) do
    """
    Thank you for your interest in joining the Young Scandinavians Club. We appreciate you taking the time to submit an application.

    Unfortunately, we are unable to approve your application at this time.

    To be eligible for membership, applicants must meet certain criteria as outlined in our bylaws. This includes demonstrating a strong connection to Scandinavian culture through one or more of the following:

    - Citizenship of a Scandinavian country (Denmark, Finland, Iceland, Norway, Sweden)
    - Birth in Scandinavia
    - Having at least one Scandinavian-born parent, grandparent, or great-grandparent
    - Having lived at least six (6) months in Scandinavia
    - Speaking one of the Scandinavian languages
    - Being the spouse of a member

    While we appreciate your enthusiasm for our community, we weren't able to determine that you met the eligibility requirements based on the information provided in your application.

    If you believe there has been an error or you have any questions regarding our membership criteria, please don't hesitate to contact us at memberships@ysc.org and we would be happy to discuss it further.

    We wish you all the best in your pursuit of Scandinavian cultural experiences.

    Med venlig hilsen, (Sincerely)

    Young Scandinavians Club
    """
    |> String.trim()
  end
end
