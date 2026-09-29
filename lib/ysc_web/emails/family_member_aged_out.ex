defmodule YscWeb.Emails.FamilyMemberAgedOut do
  @moduledoc """
  Email template for notifying a child family member that they turned 18, were
  removed from the family membership, and need their own membership to stay a
  member.
  """
  use MjmlEEx,
    mjml_template: "templates/family_member_aged_out.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name do
    "family_member_aged_out"
  end

  def get_subject do
    "You've turned 18 - time for your own YSC membership"
  end

  def membership_url, do: YscWeb.Emails.Helpers.membership_url()
end
