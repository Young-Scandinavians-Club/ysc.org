defmodule YscWeb.Emails.FamilyInvite do
  @moduledoc """
  Email template for family member invites.
  """
  use MjmlEEx,
    mjml_template: "templates/family_invite.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name do
    "family_invite"
  end

  def get_subject do
    "You're Invited to Join a Family Membership - YSC"
  end
end
