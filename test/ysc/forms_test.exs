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

    test "conduct board email uses raw phone when number cannot be parsed to national format" do
      attrs = %{
        first_name: "Sam",
        last_name: "Lee",
        email: "raw-phone@example.com",
        phone: "not-a-valid-phone-xyz",
        summary: "Report with odd phone"
      }

      changeset =
        Ysc.Forms.ConductViolationReport.changeset(
          %Ysc.Forms.ConductViolationReport{},
          attrs
        )

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _report} = Forms.create_conduct_violation_report(changeset)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "conduct_violation_board_notification",
            "params" => %{phone: "not-a-valid-phone-xyz"}
          }
        )
      end)
    end

    test "schedules board notification email with formatted phone number" do
      attrs = %{
        first_name: "Jane",
        last_name: "Smith",
        email: "reporter@example.com",
        phone: "+14155551234",
        summary: "Test violation report"
      }

      changeset =
        Ysc.Forms.ConductViolationReport.changeset(
          %Ysc.Forms.ConductViolationReport{},
          attrs
        )

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _report} = Forms.create_conduct_violation_report(changeset)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "conduct_violation_board_notification",
            "params" => %{phone: "(415) 555-1234"}
          }
        )
      end)
    end

    test "volunteer board notification includes formatted submitted_at in params",
         %{
           user: user
         } do
      attrs = %{
        email: "board-ts@example.com",
        name: "Submitted At Test",
        interest_events: true,
        interest_activities: false,
        interest_clear_lake: false,
        interest_tahoe: false,
        interest_marketing: false,
        interest_website: false,
        user_id: user.id
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Forms.create_volunteer(changeset)

        jobs = all_enqueued(worker: YscWeb.Workers.EmailNotifier)

        board_job =
          Enum.find(
            jobs,
            &(get_in(&1.args, ["template"]) == "volunteer_board_notification")
          )

        assert board_job
        submitted_at = get_in(board_job.args, ["params", "submitted_at"])
        assert is_binary(submitted_at)
        assert submitted_at =~ "20"
        assert submitted_at =~ " at "
        assert submitted_at =~ ~r/(PST|PDT)/
      end)
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

    test "schedules board notification job for valid contact form", %{
      user: user
    } do
      attrs = %{
        name: "Board Test",
        email: "board@example.com",
        subject: "Subject line",
        message:
          "This is a test message with enough characters to pass validation.",
        user_id: user.id
      }

      changeset =
        Ysc.Forms.ContactForm.changeset(%Ysc.Forms.ContactForm{}, attrs)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _contact} = Forms.create_contact_form(changeset)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{"template" => "contact_form_board_notification"}
        )
      end)
    end

    test "board notification job subject includes the contact form topic", %{
      user: user
    } do
      topic = "Question about membership & events"

      attrs = %{
        name: "Topic Test",
        email: "topic@example.com",
        subject: topic,
        message:
          "This is a test message with enough characters to pass validation.",
        user_id: user.id
      }

      changeset =
        Ysc.Forms.ContactForm.changeset(%Ysc.Forms.ContactForm{}, attrs)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _contact} = Forms.create_contact_form(changeset)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "contact_form_board_notification",
            "subject" => "New Contact Form: #{topic}"
          }
        )
      end)
    end
  end

  describe "create_volunteer/1 email jobs" do
    test "volunteer with only website interest lists Website label", %{
      user: user
    } do
      attrs = %{
        email: "website-only@example.com",
        name: "Web Only",
        interest_events: false,
        interest_activities: false,
        interest_clear_lake: false,
        interest_tahoe: false,
        interest_marketing: false,
        interest_website: true,
        user_id: user.id
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Forms.create_volunteer(changeset)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "volunteer_confirmation",
            "params" => %{interests: ["Website"]}
          }
        )
      end)
    end

    test "includes only selected interest labels in confirmation params", %{
      user: user
    } do
      attrs = %{
        email: "tahoe-only@example.com",
        name: "Tahoe Only",
        interest_events: false,
        interest_activities: false,
        interest_clear_lake: false,
        interest_tahoe: true,
        interest_marketing: false,
        interest_website: false,
        user_id: user.id
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Forms.create_volunteer(changeset)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "volunteer_confirmation",
            "params" => %{interests: ["Tahoe"]}
          }
        )
      end)
    end

    test "volunteer with only events interest lists Events/Parties label", %{
      user: user
    } do
      attrs = %{
        email: "events-only@example.com",
        name: "Events Only",
        interest_events: true,
        interest_activities: false,
        interest_clear_lake: false,
        interest_tahoe: false,
        interest_marketing: false,
        interest_website: false,
        user_id: user.id
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Forms.create_volunteer(changeset)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "volunteer_confirmation",
            "params" => %{interests: ["Events/Parties"]}
          }
        )
      end)
    end

    test "volunteer with only activities interest lists Activities label", %{
      user: user
    } do
      attrs = %{
        email: "activities-only@example.com",
        name: "Activities Only",
        interest_events: false,
        interest_activities: true,
        interest_clear_lake: false,
        interest_tahoe: false,
        interest_marketing: false,
        interest_website: false,
        user_id: user.id
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Forms.create_volunteer(changeset)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "volunteer_confirmation",
            "params" => %{interests: ["Activities"]}
          }
        )
      end)
    end

    test "volunteer with only clear lake interest lists Clear Lake label", %{
      user: user
    } do
      attrs = %{
        email: "clearlake-only@example.com",
        name: "Clear Lake Only",
        interest_events: false,
        interest_activities: false,
        interest_clear_lake: true,
        interest_tahoe: false,
        interest_marketing: false,
        interest_website: false,
        user_id: user.id
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Forms.create_volunteer(changeset)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "volunteer_confirmation",
            "params" => %{interests: ["Clear Lake"]}
          }
        )
      end)
    end

    test "volunteer with only marketing interest lists Marketing label", %{
      user: user
    } do
      attrs = %{
        email: "marketing-only@example.com",
        name: "Marketing Only",
        interest_events: false,
        interest_activities: false,
        interest_clear_lake: false,
        interest_tahoe: false,
        interest_marketing: true,
        interest_website: false,
        user_id: user.id
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Forms.create_volunteer(changeset)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "volunteer_confirmation",
            "params" => %{interests: ["Marketing"]}
          }
        )
      end)
    end

    test "schedules confirmation and board notification jobs", %{user: user} do
      attrs = %{
        email: "volunteer-jobs@example.com",
        name: "Job Tester",
        interest_events: true,
        interest_activities: true,
        interest_clear_lake: false,
        interest_tahoe: true,
        interest_marketing: false,
        interest_website: true,
        user_id: user.id
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _v} = Forms.create_volunteer(changeset)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{"template" => "volunteer_confirmation"}
        )

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{"template" => "volunteer_board_notification"}
        )
      end)
    end
  end

  describe "create_conduct_violation_report/1 extra cases" do
    test "schedules confirmation and board notification jobs" do
      attrs = %{
        first_name: "Pat",
        last_name: "Lee",
        email: "conduct-jobs@example.com",
        phone: "+14155551234",
        summary: "Summary for conduct report job test",
        anonymous: true
      }

      changeset =
        Ysc.Forms.ConductViolationReport.changeset(
          %Ysc.Forms.ConductViolationReport{},
          attrs
        )

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _report} = Forms.create_conduct_violation_report(changeset)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{"template" => "conduct_violation_confirmation"}
        )

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{"template" => "conduct_violation_board_notification"}
        )
      end)
    end

    test "includes anonymous flag in scheduled email params" do
      attrs = %{
        first_name: "Alex",
        last_name: "Kim",
        email: "anon-conduct@example.com",
        phone: "+14155559876",
        summary: "Anonymous report body text here",
        anonymous: true
      }

      changeset =
        Ysc.Forms.ConductViolationReport.changeset(
          %Ysc.Forms.ConductViolationReport{},
          attrs
        )

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _report} = Forms.create_conduct_violation_report(changeset)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "conduct_violation_board_notification",
            "params" => %{anonymous: true}
          }
        )
      end)
    end

    test "includes anonymous false in board notification params when not anonymous" do
      attrs = %{
        first_name: "Riley",
        last_name: "Ng",
        email: "non-anon-conduct@example.com",
        phone: "+14155551111",
        summary: "Non-anonymous report summary text here",
        anonymous: false
      }

      changeset =
        Ysc.Forms.ConductViolationReport.changeset(
          %Ysc.Forms.ConductViolationReport{},
          attrs
        )

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _report} = Forms.create_conduct_violation_report(changeset)

        assert_enqueued(
          worker: YscWeb.Workers.EmailNotifier,
          args: %{
            "template" => "conduct_violation_board_notification",
            "params" => %{anonymous: false}
          }
        )
      end)
    end
  end
end

defmodule Ysc.FormsTest.EmailScheduleErrorPaths do
  @moduledoc """
  Exercises `{:error, reason}` branches when Oban/Notifier scheduling fails.

  Uses `Application.put_env(:ysc, :forms_email_notifier, ...)` — must be `async: false`.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Forms
  alias Ysc.Forms.Volunteer

  defmodule NotifierErrorStub do
    @moduledoc false
    def schedule_email(_, _, _, _, _, _),
      do: {:error, :stubbed_schedule_failure}

    def schedule_email_to_board(_, _, _, _),
      do: {:error, :stubbed_schedule_failure}
  end

  setup do
    prev = Application.get_env(:ysc, :forms_email_notifier)

    Application.put_env(:ysc, :forms_email_notifier, NotifierErrorStub)

    on_exit(fn ->
      if prev == nil do
        Application.delete_env(:ysc, :forms_email_notifier)
      else
        Application.put_env(:ysc, :forms_email_notifier, prev)
      end
    end)

    :ok
  end

  describe "email scheduling error paths" do
    test "create_volunteer/1 still returns ok when notifier returns error" do
      user = user_fixture()

      attrs = %{
        email: "volunteer-err@example.com",
        name: "Err Path",
        interest_events: false,
        interest_activities: false,
        interest_clear_lake: false,
        interest_tahoe: false,
        interest_marketing: false,
        interest_website: false,
        user_id: user.id
      }

      changeset = Volunteer.changeset(%Volunteer{}, attrs)

      assert {:ok, volunteer} = Forms.create_volunteer(changeset)
      assert volunteer.email == "volunteer-err@example.com"
    end

    test "create_conduct_violation_report/1 still returns ok when notifier returns error" do
      attrs = %{
        first_name: "A",
        last_name: "B",
        email: "conduct-err@example.com",
        phone: "+14155551234",
        summary: "Summary text for conduct error path test"
      }

      changeset =
        Ysc.Forms.ConductViolationReport.changeset(
          %Ysc.Forms.ConductViolationReport{},
          attrs
        )

      assert {:ok, report} = Forms.create_conduct_violation_report(changeset)
      assert report.email == "conduct-err@example.com"
    end

    test "create_contact_form/1 still returns ok when notifier returns error" do
      user = user_fixture()

      attrs = %{
        name: "Contact Err",
        email: "contact-err@example.com",
        subject: "Subject",
        message:
          "This is a test message with enough characters to pass validation.",
        user_id: user.id
      }

      changeset =
        Ysc.Forms.ContactForm.changeset(%Ysc.Forms.ContactForm{}, attrs)

      assert {:ok, contact} = Forms.create_contact_form(changeset)
      assert contact.email == "contact-err@example.com"
    end
  end
end

defmodule Ysc.FormsTest.NotifierSuccessAndPartialErrors do
  @moduledoc """
  Stubs `forms_email_notifier` to return `%Oban.Job{}` or `{:error, _}` so success
  logging branches and per-step error branches in `send_*_emails/1` are exercised.
  """
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Forms
  alias Ysc.Forms.Volunteer

  setup do
    %{user: user_fixture()}
  end

  defmodule NotifierReturnsJobs do
    @moduledoc false
    def schedule_email(_, _, _, _, _, _), do: %Oban.Job{id: 11}

    def schedule_email_to_board(_, _, _, _), do: %Oban.Job{id: 22}
  end

  defmodule NotifierConfirmFailsBoardOk do
    @moduledoc false
    def schedule_email(_, _, _, _, _, _), do: {:error, :confirmation_failed}

    def schedule_email_to_board(_, _, _, _), do: %Oban.Job{id: 33}
  end

  defmodule NotifierConfirmOkBoardFails do
    @moduledoc false
    def schedule_email(_, _, _, _, _, _), do: %Oban.Job{id: 44}

    def schedule_email_to_board(_, _, _, _), do: {:error, :board_failed}
  end

  defmodule NotifierRaisesOnSchedule do
    @moduledoc false
    def schedule_email(_, _, _, _, _, _), do: raise("notifier boom")

    def schedule_email_to_board(_, _, _, _), do: %Oban.Job{id: 1}
  end

  defmodule NotifierRaisesOnBoardOnly do
    @moduledoc false
    def schedule_email(_, _, _, _, _, _), do: %Oban.Job{id: 1}

    def schedule_email_to_board(_, _, _, _), do: raise("board notifier boom")
  end

  defp with_notifier(module, fun) do
    prev = Application.get_env(:ysc, :forms_email_notifier)

    Application.put_env(:ysc, :forms_email_notifier, module)

    on_exit(fn ->
      if prev == nil do
        Application.delete_env(:ysc, :forms_email_notifier)
      else
        Application.put_env(:ysc, :forms_email_notifier, prev)
      end
    end)

    fun.()
  end

  describe "notifier returns %Oban.Job{} (success scheduling branches)" do
    test "create_conduct_violation_report/1 with job-returning notifier" do
      with_notifier(NotifierReturnsJobs, fn ->
        attrs = %{
          first_name: "S",
          last_name: "U",
          email: "success-conduct@example.com",
          phone: "+14155551234",
          summary: "Coverage success path for conduct emails"
        }

        changeset =
          Ysc.Forms.ConductViolationReport.changeset(
            %Ysc.Forms.ConductViolationReport{},
            attrs
          )

        assert {:ok, report} = Forms.create_conduct_violation_report(changeset)
        assert report.email == "success-conduct@example.com"
      end)
    end

    test "create_volunteer/1 with job-returning notifier", %{user: user} do
      with_notifier(NotifierReturnsJobs, fn ->
        attrs = %{
          email: "success-vol@example.com",
          name: "Vol Success",
          interest_events: false,
          interest_activities: false,
          interest_clear_lake: false,
          interest_tahoe: false,
          interest_marketing: false,
          interest_website: false,
          user_id: user.id
        }

        changeset = Volunteer.changeset(%Volunteer{}, attrs)

        assert {:ok, v} = Forms.create_volunteer(changeset)
        assert v.email == "success-vol@example.com"
      end)
    end

    test "create_contact_form/1 with job-returning notifier", %{user: user} do
      with_notifier(NotifierReturnsJobs, fn ->
        attrs = %{
          name: "C Success",
          email: "success-contact@example.com",
          subject: "Hello",
          message:
            "This is a test message with enough characters to pass validation.",
          user_id: user.id
        }

        changeset =
          Ysc.Forms.ContactForm.changeset(%Ysc.Forms.ContactForm{}, attrs)

        assert {:ok, c} = Forms.create_contact_form(changeset)
        assert c.email == "success-contact@example.com"
      end)
    end
  end

  describe "notifier partial failures (one of two schedules returns error)" do
    test "conduct: confirmation fails, board still schedules" do
      with_notifier(NotifierConfirmFailsBoardOk, fn ->
        attrs = %{
          first_name: "P",
          last_name: "E",
          email: "partial-conduct@example.com",
          phone: "+14155551234",
          summary: "Partial error path conduct"
        }

        changeset =
          Ysc.Forms.ConductViolationReport.changeset(
            %Ysc.Forms.ConductViolationReport{},
            attrs
          )

        assert {:ok, _} = Forms.create_conduct_violation_report(changeset)
      end)
    end

    test "conduct: confirmation ok, board fails" do
      with_notifier(NotifierConfirmOkBoardFails, fn ->
        attrs = %{
          first_name: "P",
          last_name: "B",
          email: "partial-board-conduct@example.com",
          phone: "+14155551234",
          summary: "Board schedule error path"
        }

        changeset =
          Ysc.Forms.ConductViolationReport.changeset(
            %Ysc.Forms.ConductViolationReport{},
            attrs
          )

        assert {:ok, _} = Forms.create_conduct_violation_report(changeset)
      end)
    end

    test "volunteer: confirmation fails, board ok", %{user: user} do
      with_notifier(NotifierConfirmFailsBoardOk, fn ->
        attrs = %{
          email: "partial-vol@example.com",
          name: "V",
          interest_events: false,
          interest_activities: false,
          interest_clear_lake: false,
          interest_tahoe: false,
          interest_marketing: false,
          interest_website: false,
          user_id: user.id
        }

        changeset = Volunteer.changeset(%Volunteer{}, attrs)
        assert {:ok, _} = Forms.create_volunteer(changeset)
      end)
    end

    test "volunteer: confirmation ok, board fails", %{user: user} do
      with_notifier(NotifierConfirmOkBoardFails, fn ->
        attrs = %{
          email: "partial-vol-board@example.com",
          name: "V2",
          interest_events: false,
          interest_activities: false,
          interest_clear_lake: false,
          interest_tahoe: false,
          interest_marketing: false,
          interest_website: false,
          user_id: user.id
        }

        changeset = Volunteer.changeset(%Volunteer{}, attrs)
        assert {:ok, _} = Forms.create_volunteer(changeset)
      end)
    end

    test "contact form: board schedule error only", %{user: user} do
      with_notifier(NotifierConfirmOkBoardFails, fn ->
        attrs = %{
          name: "C",
          email: "partial-contact@example.com",
          subject: "Subj",
          message:
            "This is a test message with enough characters to pass validation.",
          user_id: user.id
        }

        changeset =
          Ysc.Forms.ContactForm.changeset(%Ysc.Forms.ContactForm{}, attrs)

        assert {:ok, _} = Forms.create_contact_form(changeset)
      end)
    end
  end

  describe "notifier raises (rescue path in send_*_emails)" do
    test "create_conduct_violation_report/1 still returns ok when notifier raises" do
      with_notifier(NotifierRaisesOnSchedule, fn ->
        attrs = %{
          first_name: "R",
          last_name: "E",
          email: "rescue-conduct@example.com",
          phone: "+14155551234",
          summary: "Rescue path for conduct"
        }

        changeset =
          Ysc.Forms.ConductViolationReport.changeset(
            %Ysc.Forms.ConductViolationReport{},
            attrs
          )

        assert {:ok, r} = Forms.create_conduct_violation_report(changeset)
        assert r.email == "rescue-conduct@example.com"
      end)
    end

    test "create_volunteer/1 still returns ok when confirmation schedule_email raises",
         %{
           user: user
         } do
      with_notifier(NotifierRaisesOnSchedule, fn ->
        attrs = %{
          email: "rescue-vol@example.com",
          name: "Rescue Vol",
          interest_events: false,
          interest_activities: false,
          interest_clear_lake: false,
          interest_tahoe: false,
          interest_marketing: false,
          interest_website: false,
          user_id: user.id
        }

        changeset = Volunteer.changeset(%Volunteer{}, attrs)

        assert {:ok, v} = Forms.create_volunteer(changeset)
        assert v.email == "rescue-vol@example.com"
      end)
    end

    test "create_contact_form/1 still returns ok when board schedule_email_to_board raises",
         %{
           user: user
         } do
      with_notifier(NotifierRaisesOnBoardOnly, fn ->
        attrs = %{
          name: "Rescue Contact",
          email: "rescue-contact@example.com",
          subject: "Hello",
          message:
            "This is a test message with enough characters to pass validation.",
          user_id: user.id
        }

        changeset =
          Ysc.Forms.ContactForm.changeset(%Ysc.Forms.ContactForm{}, attrs)

        assert {:ok, c} = Forms.create_contact_form(changeset)
        assert c.email == "rescue-contact@example.com"
      end)
    end
  end
end
