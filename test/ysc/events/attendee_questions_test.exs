defmodule Ysc.Events.AttendeeQuestionsTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events
  alias Ysc.Events.{AttendeeQuestion, TicketDetail, TicketTier}
  alias Ysc.Repo

  defp question_attrs(overrides \\ %{}) do
    Map.merge(%{"label" => "Dietary restrictions", "type" => "text"}, overrides)
  end

  describe "AttendeeQuestion.changeset/2" do
    test "requires a label and generates a stable id" do
      refute AttendeeQuestion.changeset(%AttendeeQuestion{}, %{}).valid?

      changeset =
        AttendeeQuestion.changeset(%AttendeeQuestion{}, question_attrs())

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :id) =~ ~r/^[0-9a-f]{10}$/

      existing = %AttendeeQuestion{id: "abc123", label: "Old"}
      changeset = AttendeeQuestion.changeset(existing, %{"label" => "New"})
      assert Ecto.Changeset.get_field(changeset, :id) == "abc123"
    end

    test "select questions need at least two distinct choices" do
      attrs = question_attrs(%{"type" => "select", "options_text" => "Small"})
      changeset = AttendeeQuestion.changeset(%AttendeeQuestion{}, attrs)

      assert %{options_text: ["add at least two choices"]} =
               errors_on(changeset)

      attrs =
        question_attrs(%{
          "type" => "select",
          "options_text" => "Small\r\n Large \n\nSmall"
        })

      changeset = AttendeeQuestion.changeset(%AttendeeQuestion{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :options) == ["Small", "Large"]
    end

    test "number bounds must be ordered and only apply to numbers" do
      attrs = question_attrs(%{"type" => "number", "min" => "5", "max" => "2"})
      changeset = AttendeeQuestion.changeset(%AttendeeQuestion{}, attrs)
      assert %{max: [_]} = errors_on(changeset)

      attrs =
        question_attrs(%{"type" => "text", "min" => "1", "prefill" => "age"})

      changeset = AttendeeQuestion.changeset(%AttendeeQuestion{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :min) == nil
      assert Ecto.Changeset.get_field(changeset, :prefill) == nil
    end

    test "presets describe the dietary and child age questions" do
      presets = Map.new(AttendeeQuestion.presets(), &{&1.key, &1.attrs})

      assert presets["dietary"].type == :text
      refute presets["dietary"].required

      assert presets["child_age"].type == :number
      assert presets["child_age"].prefill == :age
      assert presets["child_age"].help_text =~ "suitable food options"
    end
  end

  describe "ticket tier questions" do
    test "are stored on the tier and survive a reload" do
      event = event_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          type: :free,
          price: Money.new(0, :USD),
          attendee_questions: [
            question_attrs(%{"required" => "true"}),
            question_attrs(%{
              "label" => "Child's age",
              "type" => "number",
              "min" => "0",
              "prefill" => "age"
            })
          ]
        })

      reloaded = Events.get_ticket_tier!(tier.id)

      assert [diet, age] = reloaded.attendee_questions
      assert diet.label == "Dietary restrictions"
      assert diet.required
      assert age.type == :number
      assert age.prefill == :age
      assert age.min == 0
      assert diet.id != age.id
    end

    test "editing keeps question ids and dropping removes questions" do
      event = event_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          attendee_questions: [
            question_attrs(),
            question_attrs(%{"label" => "Other"})
          ]
        })

      [first, second] = tier.attendee_questions

      {:ok, updated} =
        Events.update_ticket_tier(tier, %{
          "attendee_questions" => %{
            "0" => %{"id" => first.id, "label" => "Allergies", "type" => "text"},
            "1" => %{
              "id" => second.id,
              "label" => second.label,
              "type" => "text"
            }
          },
          "attendee_questions_drop" => ["1"]
        })

      assert [%{id: id, label: "Allergies"}] = updated.attendee_questions
      assert id == first.id
    end

    test "a tier can have at most ten questions" do
      event = event_fixture()

      questions =
        for i <- 1..11, do: question_attrs(%{"label" => "Question #{i}"})

      assert {:error, changeset} =
               Events.create_ticket_tier(%{
                 name: "Too curious",
                 type: :free,
                 price: Money.new(0, :USD),
                 event_id: event.id,
                 attendee_questions: questions
               })

      assert %{attendee_questions: [_]} = errors_on(changeset)
    end

    test "question names must be distinct within a tier" do
      event = event_fixture()

      assert {:error, changeset} =
               Events.create_ticket_tier(%{
                 name: "Dupes",
                 type: :free,
                 price: Money.new(0, :USD),
                 event_id: event.id,
                 attendee_questions: [
                   question_attrs(%{"label" => "Dietary restrictions"}),
                   question_attrs(%{"label" => " dietary RESTRICTIONS"})
                 ]
               })

      assert %{attendee_questions: ["each question needs a different name"]} =
               errors_on(changeset)
    end

    test "list_tiers_with_attendee_questions/1 only returns tiers that ask" do
      event = event_fixture()
      plain = ticket_tier_fixture(%{event_id: event.id, name: "Plain"})

      asking =
        ticket_tier_fixture(%{
          event_id: event.id,
          name: "Asking",
          attendee_questions: [question_attrs()]
        })

      ids =
        event.id
        |> Events.list_tiers_with_attendee_questions()
        |> Enum.map(& &1.id)

      assert asking.id in ids
      refute plain.id in ids
    end

    test "copy_event/3 carries questions to the copied tiers" do
      user = user_fixture()

      {:ok, source} =
        Events.create_event(%{
          title: "Original",
          description: "Desc",
          state: :published,
          organizer_id: user.id,
          start_date: DateTime.add(DateTime.utc_now(), 30, :day),
          published_at: DateTime.utc_now()
        })

      original =
        ticket_tier_fixture(%{
          event_id: source.id,
          attendee_questions: [
            question_attrs(%{"required" => "true"}),
            question_attrs(%{
              "label" => "Shirt size",
              "type" => "select",
              "options_text" => "S\nM\nL"
            })
          ]
        })

      source = Repo.preload(source, :ticket_tiers, force: true)
      assert {:ok, copied} = Events.copy_event(source, user.id)

      [copied_tier] =
        Repo.all(from t in TicketTier, where: t.event_id == ^copied.id)

      assert [diet, size] = copied_tier.attendee_questions
      assert diet.label == "Dietary restrictions"
      assert diet.required
      assert size.options == ["S", "M", "L"]

      assert Enum.map(copied_tier.attendee_questions, & &1.id) ==
               Enum.map(original.attendee_questions, & &1.id)
    end
  end

  describe "ticket details with answers" do
    setup do
      event = event_fixture()
      user = user_fixture()

      tier =
        ticket_tier_fixture(%{
          event_id: event.id,
          attendee_questions: [question_attrs()]
        })

      ticket =
        %Ysc.Events.Ticket{
          id: Ecto.ULID.generate(),
          event_id: event.id,
          ticket_tier_id: tier.id,
          user_id: user.id,
          status: :confirmed,
          expires_at:
            DateTime.utc_now()
            |> DateTime.add(1, :day)
            |> DateTime.truncate(:second)
        }
        |> Repo.insert!()

      %{ticket: ticket}
    end

    test "answers-only details don't need a name", %{ticket: ticket} do
      answers = %{
        "q" => %{
          "label" => "Dietary restrictions",
          "position" => 0,
          "value" => "Vegan"
        }
      }

      assert {:ok, [detail]} =
               Events.create_ticket_details([
                 %{ticket_id: ticket.id, answers: answers, identity: false}
               ])

      assert detail.first_name == nil
      assert Repo.get!(TicketDetail, detail.id).answers == answers
    end

    test "name-only details need a name but not an email", %{ticket: ticket} do
      assert {:error, %Ecto.Changeset{}} =
               Events.create_ticket_details([
                 %{ticket_id: ticket.id, require_email: false}
               ])

      assert {:ok, [detail]} =
               Events.create_ticket_details([
                 %{
                   ticket_id: ticket.id,
                   first_name: "Kim",
                   last_name: "Parent",
                   require_email: false
                 }
               ])

      assert detail.email == nil
    end

    test "details still require a name by default", %{ticket: ticket} do
      assert {:error, %Ecto.Changeset{}} =
               Events.create_ticket_details([
                 %{ticket_id: ticket.id, answers: %{}}
               ])

      assert {:ok, [_]} =
               Events.create_ticket_details([
                 %{
                   ticket_id: ticket.id,
                   first_name: "Sam",
                   last_name: "Guest",
                   email: "sam@example.com",
                   answers: %{}
                 }
               ])
    end

    test "list_tickets_for_export/1 includes answers", %{ticket: ticket} do
      answers = %{
        "q" => %{
          "label" => "Dietary restrictions",
          "position" => 0,
          "value" => "Vegan"
        }
      }

      {:ok, _} =
        Events.create_ticket_details([
          %{ticket_id: ticket.id, answers: answers, identity: false}
        ])

      [exported] = Events.list_tickets_for_export(ticket.event_id)
      assert exported.ticket_detail.answers == answers
    end
  end
end
