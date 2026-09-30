defmodule YscWeb.AdminTicketTierQuestionsTest do
  use YscWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Ysc.Events
  alias Ysc.Events.TicketTier
  alias Ysc.Repo

  setup %{conn: conn} do
    admin = user_fixture(%{role: "admin"})
    event = event_fixture(%{organizer_id: admin.id})
    %{conn: log_in_user(conn, admin), event: event}
  end

  defp open_new_tier_form(conn, event) do
    {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")
    view |> element("#add-ticket-tier-btn-#{event.id}") |> render_click()
    view
  end

  defp tier_form(event), do: "#ticket-tier-form-#{event.id}"

  test "the attendee info section starts empty with the two presets on offer",
       %{conn: conn, event: event} do
    view = open_new_tier_form(conn, event)

    assert has_element?(view, "#attendee-info-section")
    refute has_element?(view, "#attendee-question-0")
    assert has_element?(view, "#add-question-dietary")
    assert has_element?(view, "#add-question-child_age")
    assert has_element?(view, "#add-question-custom")
  end

  test "attendee info is collapsed until something is configured",
       %{conn: conn, event: event} do
    view = open_new_tier_form(conn, event)

    assert has_element?(view, ~s(#attendee-info-toggle[aria-expanded="false"]))
    assert has_element?(view, "#attendee-info-section.hidden")

    assert has_element?(
             view,
             "#attendee-info-summary",
             "Nothing extra"
           )

    # Adding a question opens the section and shows it in the summary.
    view |> element("#add-question-dietary") |> render_click()

    assert has_element?(view, ~s(#attendee-info-toggle[aria-expanded="true"]))
    refute has_element?(view, "#attendee-info-section.hidden")
    assert has_element?(view, "#attendee-info-summary", "Dietary restrictions")
  end

  test "tiers with a NULL requires_registration still list", %{
    conn: conn,
    event: event
  } do
    tier = ticket_tier_fixture(%{event_id: event.id, name: "Legacy"})

    Repo.update_all(
      from(t in TicketTier, where: t.id == ^tier.id),
      set: [requires_registration: nil]
    )

    {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

    assert has_element?(view, "#tier-attendee-info-#{tier.id}", "None")
  end

  test "an existing tier that asks for names starts expanded",
       %{conn: conn, event: event} do
    tier =
      ticket_tier_fixture(%{event_id: event.id, requires_registration: true})

    {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")
    view |> element("#ticket-tier-actions-#{tier.id}-edit") |> render_click()

    refute has_element?(view, "#attendee-info-section.hidden")
    assert has_element?(view, "#attendee-info-summary", "Name & email")
  end

  test "price only shows for paid tiers and quantity hides when unlimited",
       %{conn: conn, event: event} do
    view = open_new_tier_form(conn, event)

    # New tiers default to free: no price field.
    refute has_element?(view, ~s(input[name="ticket_tier[price]"]))

    view
    |> form(tier_form(event), %{"ticket_tier" => %{"type" => "paid"}})
    |> render_change()

    assert has_element?(view, ~s(input[name="ticket_tier[price]"]))

    assert has_element?(view, ~s(input[name="ticket_tier[quantity]"]))

    view
    |> form(tier_form(event), %{
      "ticket_tier" => %{"unlimited_quantity" => "true"}
    })
    |> render_change()

    refute has_element?(view, ~s(input[name="ticket_tier[quantity]"]))
  end

  test "adding the dietary preset fills in its label and help text",
       %{conn: conn, event: event} do
    view = open_new_tier_form(conn, event)

    view |> element("#add-question-dietary") |> render_click()

    assert has_element?(view, "#attendee-question-0")

    assert has_element?(
             view,
             ~s(#attendee-question-0 input[value="Dietary restrictions"])
           )

    # A preset is offered once.
    refute has_element?(view, "#add-question-dietary")
  end

  test "an admin can build questions and save them on a new tier",
       %{conn: conn, event: event} do
    view = open_new_tier_form(conn, event)

    view |> element("#add-question-dietary") |> render_click()
    view |> element("#add-question-child_age") |> render_click()

    assert has_element?(view, "#attendee-question-1")
    # The number question offers bounds and age pre-fill.
    assert has_element?(view, "#attendee-question-1 select option[value=age]")

    view
    |> form(tier_form(event), %{
      "ticket_tier" => %{
        "name" => "Kids dinner",
        "type" => "free",
        "unlimited_quantity" => "true"
      }
    })
    |> render_submit()

    tier = Repo.one!(from(t in TicketTier, where: t.name == "Kids dinner"))

    assert [diet, age] = tier.attendee_questions
    assert diet.label == "Dietary restrictions"
    refute diet.required
    assert age.label == "Child's age"
    assert age.type == :number
    assert age.prefill == :age
    assert age.help_text =~ "suitable food options"
  end

  test "custom questions can be a list to pick from", %{
    conn: conn,
    event: event
  } do
    view = open_new_tier_form(conn, event)

    view |> element("#add-question-custom") |> render_click()

    view
    |> form(tier_form(event), %{
      "ticket_tier" => %{
        "name" => "Shirts",
        "type" => "free",
        "unlimited_quantity" => "true",
        "attendee_questions" => %{
          "0" => %{
            "label" => "Shirt size",
            "type" => "select",
            "required" => "true"
          }
        }
      }
    })
    |> render_change()

    # Picking "list" reveals the choices box.
    assert has_element?(view, "#attendee-question-0 textarea")

    view
    |> form(tier_form(event), %{
      "ticket_tier" => %{
        "attendee_questions" => %{"0" => %{"options_text" => "S\nM\nL"}}
      }
    })
    |> render_submit()

    tier = Repo.one!(from(t in TicketTier, where: t.name == "Shirts"))

    assert [%{type: :select, required: true, options: ["S", "M", "L"]}] =
             tier.attendee_questions
  end

  test "a select question without choices is rejected", %{
    conn: conn,
    event: event
  } do
    view = open_new_tier_form(conn, event)

    view |> element("#add-question-custom") |> render_click()

    html =
      view
      |> form(tier_form(event), %{
        "ticket_tier" => %{
          "name" => "Broken",
          "type" => "free",
          "unlimited_quantity" => "true",
          "attendee_questions" => %{
            "0" => %{"label" => "Pick", "type" => "select"}
          }
        }
      })
      |> render_submit()

    assert html =~ "add at least two choices"
    assert Repo.get_by(TicketTier, name: "Broken") == nil
  end

  test "questions can be copied from another tier of the event",
       %{conn: conn, event: event} do
    source =
      ticket_tier_fixture(%{
        event_id: event.id,
        name: "Adults",
        attendee_questions: [
          %{"label" => "Dietary restrictions", "type" => "text"}
        ]
      })

    view = open_new_tier_form(conn, event)

    assert has_element?(view, "#copy-questions-#{source.id}")
    view |> element("#copy-questions-#{source.id}") |> render_click()

    assert has_element?(
             view,
             ~s(#attendee-question-0 input[value="Dietary restrictions"])
           )

    # Copying again doesn't duplicate what is already there.
    view |> element("#copy-questions-#{source.id}") |> render_click()
    refute has_element?(view, "#attendee-question-1")
  end

  test "editing a tier shows its questions and removing one saves",
       %{conn: conn, event: event} do
    tier =
      ticket_tier_fixture(%{
        event_id: event.id,
        name: "Adults",
        attendee_questions: [
          %{"label" => "Dietary restrictions", "type" => "text"},
          %{"label" => "Seat preference", "type" => "text"}
        ]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/events/#{event.id}/tickets")

    assert has_element?(
             view,
             "#tier-attendee-info-#{tier.id}",
             "Dietary restrictions"
           )

    assert has_element?(
             view,
             "#tier-attendee-info-#{tier.id}",
             "Seat preference"
           )

    view |> element("#ticket-tier-actions-#{tier.id}-edit") |> render_click()

    assert has_element?(view, "#attendee-question-0")
    assert has_element?(view, "#attendee-question-1")

    view
    |> form("#edit-ticket-tier-form-#{tier.id}", %{
      "ticket_tier" => %{"attendee_questions_drop" => ["1"]}
    })
    |> render_submit()

    assert [%{label: "Dietary restrictions"}] =
             Events.get_ticket_tier!(tier.id).attendee_questions
  end
end
