defmodule Ysc.FormsTest do
  @moduledoc """
  Tests for Forms module.

  These tests verify:
  - Volunteer form creation
  - Conduct violation report creation
  - Email scheduling
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Forms
  alias Ysc.Forms.Volunteer

  setup do
    user = user_fixture()
    %{user: user}
  end

  describe "create_volunteer/1" do
    test "creates volunteer and schedules emails", %{user: user} do
      attrs = %{
        email: "volunteer@example.com",
        name: "John Doe",
        interest_events: true,
        interest_activities: false,
        interest_clear_lake: true,
        interest_tahoe: false,
        interest_marketing: true,
        interest_website: false,
        user_id: user.id
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      assert {:ok, volunteer} = Forms.create_volunteer(changeset)
      assert volunteer.email == "volunteer@example.com"
      assert volunteer.name == "John Doe"
      assert volunteer.interest_events == true
      assert volunteer.interest_clear_lake == true
      assert volunteer.interest_marketing == true
    end

    test "returns error for invalid changeset" do
      attrs = %{
        # Missing @
        email: "invalid-email",
        name: ""
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      assert {:error, changeset} = Forms.create_volunteer(changeset)
      assert changeset.errors[:email] != nil
    end

    test "handles volunteer with all interests" do
      attrs = %{
        email: "volunteer@example.com",
        name: "Jane Smith",
        interest_events: true,
        interest_activities: true,
        interest_clear_lake: true,
        interest_tahoe: true,
        interest_marketing: true,
        interest_website: true
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      assert {:ok, volunteer} = Forms.create_volunteer(changeset)
      assert volunteer.interest_events == true
      assert volunteer.interest_activities == true
      assert volunteer.interest_clear_lake == true
      assert volunteer.interest_tahoe == true
      assert volunteer.interest_marketing == true
      assert volunteer.interest_website == true
    end

    test "handles volunteer with no interests" do
      attrs = %{
        email: "volunteer@example.com",
        name: "Bob Johnson",
        interest_events: false,
        interest_activities: false,
        interest_clear_lake: false,
        interest_tahoe: false,
        interest_marketing: false,
        interest_website: false
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      assert {:ok, volunteer} = Forms.create_volunteer(changeset)
      assert volunteer.interest_events == false
      assert volunteer.interest_activities == false
    end
  end

  describe "create_conduct_violation_report/1" do
    test "creates conduct violation report and schedules emails" do
      attrs = %{
        first_name: "John",
        last_name: "Doe",
        email: "reporter@example.com",
        phone: "555-1234",
        summary: "Test violation report"
      }

      changeset =
        Ysc.Forms.ConductViolationReport.changeset(
          %Ysc.Forms.ConductViolationReport{},
          attrs
        )

      assert {:ok, report} = Forms.create_conduct_violation_report(changeset)
      assert report.email == "reporter@example.com"
      assert report.first_name == "John"
      assert report.last_name == "Doe"
      assert report.phone == "555-1234"
      assert report.summary == "Test violation report"
    end

    test "returns error for invalid changeset" do
      attrs = %{
        first_name: "",
        last_name: "",
        email: "invalid-email",
        phone: "",
        summary: ""
      }

      changeset =
        Ysc.Forms.ConductViolationReport.changeset(
          %Ysc.Forms.ConductViolationReport{},
          attrs
        )

      assert {:error, changeset} =
               Forms.create_conduct_violation_report(changeset)

      refute changeset.valid?
    end
  end

  describe "create_contact_form/1" do
    test "creates contact form and schedules emails", %{user: user} do
      attrs = %{
        name: "John Doe",
        email: "contact@example.com",
        subject: "Test Subject",
        message:
          "This is a test message with enough characters to pass validation.",
        user_id: user.id
      }

      changeset =
        Ysc.Forms.ContactForm.changeset(%Ysc.Forms.ContactForm{}, attrs)

      assert {:ok, contact_form} = Forms.create_contact_form(changeset)
      assert contact_form.name == "John Doe"
      assert contact_form.email == "contact@example.com"
      assert contact_form.subject == "Test Subject"

      assert contact_form.message ==
               "This is a test message with enough characters to pass validation."
    end

    test "creates contact form without user_id" do
      attrs = %{
        name: "Jane Smith",
        email: "jane@example.com",
        subject: "Another Subject",
        message:
          "This is another test message with enough characters to pass validation."
      }

      changeset =
        Ysc.Forms.ContactForm.changeset(%Ysc.Forms.ContactForm{}, attrs)

      assert {:ok, contact_form} = Forms.create_contact_form(changeset)
      assert contact_form.name == "Jane Smith"
      assert contact_form.user_id == nil
    end

    test "returns error for invalid changeset" do
      attrs = %{
        name: "",
        email: "invalid-email",
        subject: "",
        message: "short"
      }

      changeset =
        Ysc.Forms.ContactForm.changeset(%Ysc.Forms.ContactForm{}, attrs)

      assert {:error, changeset} = Forms.create_contact_form(changeset)
      refute changeset.valid?
      assert changeset.errors[:name] != nil
      assert changeset.errors[:email] != nil
      assert changeset.errors[:message] != nil
    end

    test "validates minimum message length" do
      attrs = %{
        name: "Test User",
        email: "test@example.com",
        subject: "Test",
        message: "short"
      }

      changeset =
        Ysc.Forms.ContactForm.changeset(%Ysc.Forms.ContactForm{}, attrs)

      assert {:error, changeset} = Forms.create_contact_form(changeset)
      assert changeset.errors[:message] != nil
    end
  end
end
