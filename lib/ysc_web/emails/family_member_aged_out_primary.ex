defmodule YscWeb.Emails.FamilyMemberAgedOutPrimary do
  @moduledoc """
  Email template for notifying a family membership holder that a child on their
  membership turned 18 and was removed from it.
  """
  use MjmlEEx,
    mjml_template: "templates/family_member_aged_out_primary.mjml.eex",
    layout: YscWeb.Emails.BaseLayout

  def get_template_name do
    "family_member_aged_out_primary"
  end

  def get_subject do
    "A family member has aged out of your YSC membership"
  end

  def family_management_url,
    do: YscWeb.Emails.Helpers.absolute_url("/users/settings/family")
end
