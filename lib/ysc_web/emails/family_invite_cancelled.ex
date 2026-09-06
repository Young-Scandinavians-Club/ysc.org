defmodule YscWeb.Emails.FamilyInviteCancelled do
  @moduledoc """
  Email template for family invite cancellation notifications.

  Sent when a family membership invitation is revoked/cancelled.
  """
  use MjmlEEx,
    mjml_template: "templates/family_invite_cancelled.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name do
    "family_invite_cancelled"
  end

  def get_subject do
    "Your family membership invitation was cancelled - YSC"
  end

  def membership_email, do: Ysc.EmailConfig.membership_email()
end
