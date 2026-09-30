defmodule Ysc.Events.AttendeeInfoTest do
  use ExUnit.Case, async: true

  alias Ysc.Events.{AttendeeInfo, AttendeeQuestion}

  defp question(attrs) do
    struct(
      AttendeeQuestion,
      Map.merge(
        %{
          id: "q1",
          label: "Question",
          type: :text,
          required: false,
          options: []
        },
        Map.new(attrs)
      )
    )
  end

  describe "tier configuration" do
    test "identity and questions are independent" do
      assert AttendeeInfo.collects_identity?(%{requires_registration: true})
      refute AttendeeInfo.collects_identity?(%{requires_registration: false})
      refute AttendeeInfo.collects_identity?(%{requires_registration: nil})

      only_questions = %{
        requires_registration: false,
        attendee_questions: [question(id: "a")]
      }

      assert AttendeeInfo.collects_info?(only_questions)
      refute AttendeeInfo.collects_identity?(only_questions)

      refute AttendeeInfo.collects_info?(%{
               requires_registration: false,
               attendee_questions: []
             })
    end

    test "donation tiers never collect anything" do
      tier = %{
        type: :donation,
        requires_registration: true,
        attendee_questions: [question(id: "a")]
      }

      refute AttendeeInfo.collects_info?(tier)
      assert AttendeeInfo.questions(tier) == []
    end

    test "tickets_needing_info keeps only tickets whose tier asks something" do
      asks = %{ticket_tier: %{requires_registration: true}}
      silent = %{ticket_tier: %{requires_registration: false}}
      no_tier = %{ticket_tier: nil}

      assert AttendeeInfo.tickets_needing_info([asks, silent, no_tier]) == [
               asks
             ]
    end
  end

  describe "cast_answers/2" do
    test "stores typed values with a snapshot of the question" do
      questions = [
        question(id: "diet", label: "Dietary restrictions"),
        question(
          id: "age",
          label: "Child's age",
          type: :number,
          min: 0,
          max: 17
        ),
        question(id: "veg", label: "Vegetarian?", type: :yes_no),
        question(
          id: "size",
          label: "Shirt size",
          type: :select,
          options: ["S", "M", "L"]
        )
      ]

      raw = %{
        "diet" => "  No nuts ",
        "age" => "7",
        "veg" => "yes",
        "size" => "M"
      }

      assert {:ok, answers} = AttendeeInfo.cast_answers(questions, raw)

      assert answers["diet"] == %{
               "label" => "Dietary restrictions",
               "type" => "text",
               "position" => 0,
               "value" => "No nuts"
             }

      assert answers["age"]["value"] == 7
      assert answers["veg"]["value"] == true
      assert answers["size"]["value"] == "M"
      assert answers["size"]["position"] == 3
    end

    test "blank optional answers are left out" do
      questions = [question(id: "diet"), question(id: "age", type: :number)]

      assert {:ok, answers} =
               AttendeeInfo.cast_answers(questions, %{
                 "diet" => "  ",
                 "age" => ""
               })

      assert answers == %{}
    end

    test "required questions must be answered" do
      questions = [question(id: "diet", required: true)]

      assert {:error, %{"diet" => "is required"}} =
               AttendeeInfo.cast_answers(questions, %{})

      assert {:error, %{"diet" => "is required"}} =
               AttendeeInfo.cast_answers(questions, %{"diet" => "   "})
    end

    test "numbers must be whole and within bounds" do
      questions = [question(id: "age", type: :number, min: 0, max: 17)]

      assert {:error, %{"age" => "must be a whole number"}} =
               AttendeeInfo.cast_answers(questions, %{"age" => "seven"})

      assert {:error, %{"age" => "must be a whole number"}} =
               AttendeeInfo.cast_answers(questions, %{"age" => "7.5"})

      assert {:error, %{"age" => "must be at least 0"}} =
               AttendeeInfo.cast_answers(questions, %{"age" => "-1"})

      assert {:error, %{"age" => "must be at most 17"}} =
               AttendeeInfo.cast_answers(questions, %{"age" => "18"})

      assert {:ok, %{"age" => %{"value" => 0}}} =
               AttendeeInfo.cast_answers(questions, %{"age" => "0"})
    end

    test "yes/no and select values are checked" do
      questions = [
        question(id: "yn", type: :yes_no),
        question(id: "pick", type: :select, options: ["A", "B"])
      ]

      assert {:error, errors} =
               AttendeeInfo.cast_answers(questions, %{
                 "yn" => "maybe",
                 "pick" => "C"
               })

      assert errors["yn"] == "choose yes or no"
      assert errors["pick"] == "choose one of the options"

      assert {:ok, %{"yn" => %{"value" => false}, "pick" => %{"value" => "B"}}} =
               AttendeeInfo.cast_answers(questions, %{
                 "yn" => "no",
                 "pick" => "B"
               })
    end

    test "text has a length limit" do
      questions = [question(id: "diet")]

      assert {:error, %{"diet" => _}} =
               AttendeeInfo.cast_answers(questions, %{
                 "diet" => String.duplicate("a", 501)
               })
    end
  end

  describe "round trip and display" do
    test "answers_to_form/1 reverses cast_answers/2" do
      questions = [
        question(id: "diet"),
        question(id: "age", type: :number),
        question(id: "yn", type: :yes_no)
      ]

      raw = %{"diet" => "Vegan", "age" => "9", "yn" => "no"}
      {:ok, answers} = AttendeeInfo.cast_answers(questions, raw)

      assert AttendeeInfo.answers_to_form(answers) == raw
    end

    test "display_answers/1 is ordered by question position and skips blanks" do
      answers = %{
        "b" => %{"label" => "Second", "position" => 1, "value" => true},
        "a" => %{"label" => "First", "position" => 0, "value" => "Vegan"},
        "c" => %{"label" => "Empty", "position" => 2, "value" => ""}
      }

      assert AttendeeInfo.display_answers(%{answers: answers}) == [
               %{label: "First", value: "Vegan"},
               %{label: "Second", value: "Yes"}
             ]

      assert AttendeeInfo.display_answers(nil) == []
      assert AttendeeInfo.display_answers(%{answers: %{}}) == []
    end
  end

  describe "CSV export helpers" do
    test "columns are grouped by label across tiers, in question order" do
      adult = %{
        answers: %{
          "x1" => %{
            "label" => "Dietary restrictions",
            "position" => 0,
            "value" => "None"
          }
        }
      }

      kid = %{
        answers: %{
          "y1" => %{
            "label" => "Dietary restrictions",
            "position" => 0,
            "value" => "Nuts"
          },
          "y2" => %{"label" => "Child's age", "position" => 1, "value" => 6}
        }
      }

      assert AttendeeInfo.export_columns([], [adult, kid, %{answers: %{}}]) == [
               "Dietary restrictions",
               "Child's age"
             ]

      assert AttendeeInfo.export_value(kid, "Child's age") == "6"
      assert AttendeeInfo.export_value(kid, "Dietary restrictions") == "Nuts"
      assert AttendeeInfo.export_value(adult, "Child's age") == ""
      assert AttendeeInfo.export_value(nil, "Child's age") == ""
    end

    test "configured questions get a column even before anyone answers" do
      tier = %{
        attendee_questions: [
          question(id: "a", label: "Dietary restrictions"),
          question(id: "b", label: "Child's age")
        ]
      }

      old_answer = %{
        answers: %{
          "z" => %{
            "label" => "Removed question",
            "position" => 0,
            "value" => "x"
          }
        }
      }

      assert AttendeeInfo.export_columns([tier], [old_answer]) == [
               "Dietary restrictions",
               "Removed question",
               "Child's age"
             ]

      assert AttendeeInfo.export_columns([%{attendee_questions: []}], []) == []
    end
  end

  describe "age pre-fill" do
    test "age_on/2 counts completed years" do
      assert AttendeeInfo.age_on(~D[2018-06-15], ~D[2026-06-14]) == 7
      assert AttendeeInfo.age_on(~D[2018-06-15], ~D[2026-06-15]) == 8
      assert AttendeeInfo.age_on(~D[2026-06-15], ~D[2026-06-15]) == 0
      assert AttendeeInfo.age_on(~D[2027-01-01], ~D[2026-06-15]) == nil
      assert AttendeeInfo.age_on(nil, ~D[2026-06-15]) == nil
    end

    test "event_date/1 reads the calendar day of the event" do
      assert AttendeeInfo.event_date(%{start_date: ~D[2026-08-01]}) ==
               ~D[2026-08-01]

      assert AttendeeInfo.event_date(%{start_date: ~U[2026-08-01 00:00:00Z]}) ==
               ~D[2026-08-01]
    end

    test "apply_prefill/4 fills only age questions and clears them for nobody" do
      questions = [
        question(id: "age", type: :number, prefill: :age),
        question(id: "diet")
      ]

      child = %{date_of_birth: ~D[2019-03-01]}
      on_date = ~D[2026-08-01]

      assert AttendeeInfo.apply_prefill(
               %{"diet" => "Vegan"},
               questions,
               child,
               on_date
             ) ==
               %{"age" => "7", "diet" => "Vegan"}

      assert AttendeeInfo.apply_prefill(
               %{"age" => "7"},
               questions,
               nil,
               on_date
             ) ==
               %{"age" => ""}

      assert AttendeeInfo.apply_prefill(
               %{},
               questions,
               %{date_of_birth: nil},
               on_date
             ) ==
               %{"age" => ""}
    end
  end

  describe "checkout state" do
    setup do
      me = %{
        id: "user-me",
        first_name: "Pat",
        last_name: "Parent",
        email: "pat@example.com",
        date_of_birth: ~D[1985-01-01]
      }

      kid = %{
        id: "user-kid",
        first_name: "Kim",
        last_name: "Parent",
        email: "kim@example.com",
        date_of_birth: ~D[2019-05-05]
      }

      tier = %{
        requires_registration: true,
        attendee_questions: [
          question(id: "age", type: :number, required: true, prefill: :age)
        ]
      }

      ticket = %{id: "t1", ticket_tier: tier}

      state = %{
        tickets_for_me: %{},
        selected_family_members: %{},
        family_members: [kid],
        ticket_details_form: %{},
        current_user: me
      }

      %{ticket: ticket, state: state, me: me, kid: kid}
    end

    test "resolves who the ticket is for", %{
      ticket: ticket,
      state: state,
      kid: kid
    } do
      assert %{source: :other} = AttendeeInfo.resolve(ticket, state)

      for_me = %{state | tickets_for_me: %{"t1" => true}}

      assert %{source: :me, identity: %{first_name: "Pat"}} =
               AttendeeInfo.resolve(ticket, for_me)

      family = %{state | selected_family_members: %{"t1" => kid.id}}

      assert %{source: :family, identity: %{email: "kim@example.com"}} =
               AttendeeInfo.resolve(ticket, family)
    end

    test "is complete only with identity and required answers", %{
      ticket: ticket,
      state: state
    } do
      refute AttendeeInfo.complete?(ticket, state)

      typed = %{
        state
        | ticket_details_form: %{
            "t1" => %{
              first_name: "Sam",
              last_name: "Guest",
              email: "sam@example.com",
              answers: %{"age" => "8"}
            }
          }
      }

      assert AttendeeInfo.complete?(ticket, typed)

      no_age = put_in(typed.ticket_details_form["t1"].answers, %{"age" => ""})
      refute AttendeeInfo.complete?(ticket, no_age)

      bad_email = put_in(typed.ticket_details_form["t1"].email, "nope")
      refute AttendeeInfo.complete?(ticket, bad_email)
    end

    test "questions-only tickets don't need a name", %{state: state} do
      ticket = %{
        id: "t2",
        ticket_tier: %{
          requires_registration: false,
          attendee_questions: [question(id: "diet", required: true)]
        }
      }

      refute AttendeeInfo.complete?(ticket, state)

      answered = %{
        state
        | ticket_details_form: %{"t2" => %{answers: %{"diet" => "Vegan"}}}
      }

      assert AttendeeInfo.complete?(ticket, answered)

      assert {:ok, detail} = AttendeeInfo.build_detail(ticket, answered)
      assert detail.identity == false
      assert detail.ticket_id == "t2"
      assert detail.answers["diet"]["value"] == "Vegan"
      refute Map.has_key?(detail, :first_name)
    end

    test "build_detail/2 carries identity for tickets that collect it", %{
      ticket: ticket,
      state: state
    } do
      for_me = %{
        state
        | tickets_for_me: %{"t1" => true},
          ticket_details_form: %{"t1" => %{answers: %{"age" => "40"}}}
      }

      assert {:ok, detail} = AttendeeInfo.build_detail(ticket, for_me)
      assert detail.identity == true
      assert detail.first_name == "Pat"
      assert detail.email == "pat@example.com"
      assert detail.answers["age"]["value"] == 40

      assert {:error, :identity} = AttendeeInfo.build_detail(ticket, state)
    end
  end
end
