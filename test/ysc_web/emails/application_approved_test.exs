defmodule YscWeb.Emails.ApplicationApprovedTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.Emails.ApplicationApproved
  alias YscWeb.Emails.ApplicationApprovedFamilyLinked

  test "get_template_name/0 and get_subject/0" do
    assert ApplicationApproved.get_template_name() == "application_approved"
    assert ApplicationApproved.get_subject() =~ "Velkommen"
  end

  test "upcoming_events_url/0 and pay_membership_url/0 include paths" do
    assert ApplicationApproved.upcoming_events_url() =~ "/events"
    assert ApplicationApproved.pay_membership_url() =~ "/users/membership"
  end

  test "render/1 produces HTML email body" do
    user = user_fixture()

    assigns = %{
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email
    }

    html = ApplicationApproved.render(assigns)
    assert is_binary(html)
    assert html =~ user.first_name
  end

  describe "ApplicationApprovedFamilyLinked" do
    test "get_template_name/0 and get_subject/0" do
      assert ApplicationApprovedFamilyLinked.get_template_name() ==
               "application_approved_family_linked"

      assert ApplicationApprovedFamilyLinked.get_subject() =~ "Velkommen"
    end

    test "upcoming_events_url/0 and home_url/0 include paths" do
      assert ApplicationApprovedFamilyLinked.upcoming_events_url() =~ "/events"
      assert ApplicationApprovedFamilyLinked.home_url() =~ "/"
    end

    test "render/1 produces HTML email body" do
      user = user_fixture()

      assigns = %{
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email
      }

      html = ApplicationApprovedFamilyLinked.render(assigns)
      assert is_binary(html)
      assert html =~ user.first_name
    end
  end
end
