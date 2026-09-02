defmodule YscWeb.Emails.FamilyMemberRemoved do
  @moduledoc """
  Email template for notifying users when they are removed from a family membership.
  """
  use MjmlEEx,
    mjml_template: "templates/family_member_removed.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name do
    "family_member_removed"
  end

  def get_subject do
    "Removed from Family Membership - YSC"
  end

  def membership_url, do: YscWeb.Emails.Helpers.membership_url()
end
