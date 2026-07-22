defmodule YscWeb.Emails.FamilyInviteAccepted do
  @moduledoc """
  Email template for notifying the inviter when a family invite is accepted.
  """
  use MjmlEEx,
    mjml_template: "templates/family_invite_accepted.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name do
    "family_invite_accepted"
  end

  def get_subject do
    "Family Invitation Accepted - YSC"
  end
end
