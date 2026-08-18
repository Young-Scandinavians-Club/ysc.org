defmodule YscWeb.AgendaEditComponentTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.EventsFixtures

  alias Ysc.Agendas
  alias YscWeb.AgendaEditComponent

  setup do
    event = event_fixture()
    {:ok, agenda} = Agendas.create_agenda(event, %{title: "Test Agenda"})
    %{event: event, agenda: agenda}
  end

  describe "rendering - empty agenda" do
    test "displays add slot button", %{agenda: agenda, event: event} do
      agenda = Agendas.get_agenda!(agenda.id)

      html =
        render_component(AgendaEditComponent, %{
          id: "agenda-edit-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "Add Slot"
    end

    test "renders empty agenda items container", %{agenda: agenda, event: event} do
      agenda = Agendas.get_agenda!(agenda.id)

      html =
        render_component(AgendaEditComponent, %{
          id: "agenda-edit-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "agenda-#{agenda.id}"
      assert html =~ "phx-update=\"stream\""
    end

    test "has sortable hook for drag and drop", %{agenda: agenda, event: event} do
      agenda = Agendas.get_agenda!(agenda.id)

      html =
        render_component(AgendaEditComponent, %{
          id: "agenda-edit-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "phx-hook=\"Sortable\""
    end
  end

  describe "rendering - with agenda items" do
    test "displays agenda item title field", %{agenda: agenda, event: event} do
      {:ok, _item} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Opening Remarks",
          start_time: ~T[09:00:00],
          end_time: ~T[09:30:00]
        })

      agenda = Agendas.get_agenda!(agenda.id)

      html =
        render_component(AgendaEditComponent, %{
          id: "agenda-edit-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "Opening Remarks"
      assert html =~ "placeholder=\"Agenda Item Title\""
    end

    test "displays start and end time fields", %{agenda: agenda, event: event} do
      {:ok, _item} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Session",
          start_time: ~T[10:00:00],
          end_time: ~T[11:00:00]
        })

      agenda = Agendas.get_agenda!(agenda.id)

      html =
        render_component(AgendaEditComponent, %{
          id: "agenda-edit-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "type=\"time\""
      assert html =~ "name=\"agenda_item[start_time]\""
      assert html =~ "name=\"agenda_item[end_time]\""
      assert html =~ "value=\"10:00:00\""
      assert html =~ "value=\"11:00:00\""
    end

    test "displays delete button for agenda item", %{
      agenda: agenda,
      event: event
    } do
      {:ok, _item} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Lunch",
          start_time: ~T[12:00:00]
        })

      agenda = Agendas.get_agenda!(agenda.id)

      html =
        render_component(AgendaEditComponent, %{
          id: "agenda-edit-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "hero-trash"
      assert html =~ "phx-click"
    end

    test "displays drag handle for reordering", %{agenda: agenda, event: event} do
      {:ok, _item} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Item 1"
        })

      agenda = Agendas.get_agenda!(agenda.id)

      html =
        render_component(AgendaEditComponent, %{
          id: "agenda-edit-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "drag-handle"
      assert html =~ "hero-arrows-up-down"
    end

    test "renders multiple agenda items", %{agenda: agenda, event: event} do
      {:ok, _item1} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Item 1",
          start_time: ~T[09:00:00]
        })

      {:ok, _item2} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Item 2",
          start_time: ~T[10:00:00]
        })

      agenda = Agendas.get_agenda!(agenda.id)

      html =
        render_component(AgendaEditComponent, %{
          id: "agenda-edit-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "Item 1"
      assert html =~ "Item 2"
    end
  end

  describe "form behavior" do
    test "form submits on blur", %{agenda: agenda, event: event} do
      {:ok, _item} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Test"
        })

      agenda = Agendas.get_agenda!(agenda.id)

      html =
        render_component(AgendaEditComponent, %{
          id: "agenda-edit-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "phx-submit=\"save\""
      assert html =~ "phx-blur"
    end

    test "form submits on save", %{agenda: agenda, event: event} do
      {:ok, _item} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Test"
        })

      agenda = Agendas.get_agenda!(agenda.id)

      html =
        render_component(AgendaEditComponent, %{
          id: "agenda-edit-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "phx-submit=\"save\""
    end

    test "debounces validate events to limit database load", %{
      agenda: agenda,
      event: event
    } do
      {:ok, _item} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Test"
        })

      agenda = Agendas.get_agenda!(agenda.id)

      html =
        render_component(AgendaEditComponent, %{
          id: "agenda-edit-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "phx-debounce=\"300\""
    end

    test "form auto-submits on blur", %{agenda: agenda, event: event} do
      {:ok, _item} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Test"
        })

      agenda = Agendas.get_agenda!(agenda.id)

      html =
        render_component(AgendaEditComponent, %{
          id: "agenda-edit-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "phx-blur"
    end
  end

  describe "add slot button" do
    test "has correct phx-click event", %{agenda: agenda, event: event} do
      agenda = Agendas.get_agenda!(agenda.id)

      html =
        render_component(AgendaEditComponent, %{
          id: "agenda-edit-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "phx-click"
      assert html =~ "Add Slot"
    end
  end

  describe "chronological warning" do
    test "is hidden when timed items are in start-time order", %{
      agenda: agenda,
      event: event
    } do
      {:ok, _} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Morning",
          start_time: ~T[09:00:00],
          end_time: ~T[09:30:00]
        })

      {:ok, _} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Afternoon",
          start_time: ~T[10:00:00],
          end_time: ~T[10:30:00]
        })

      html = render_agenda(agenda, event)

      refute html =~ "Chronological Warning"
    end

    test "is shown when a later slot starts before an earlier one", %{
      agenda: agenda,
      event: event
    } do
      {:ok, _} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Late slot first",
          start_time: ~T[11:00:00]
        })

      {:ok, _} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Earlier slot second",
          start_time: ~T[09:00:00]
        })

      html = render_agenda(agenda, event)

      assert html =~ "Chronological Warning"
      assert html =~ "out of order"
    end

    test "is shown when an earlier slot's end overlaps the next start", %{
      agenda: agenda,
      event: event
    } do
      {:ok, _} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Overlapping first",
          start_time: ~T[09:00:00],
          end_time: ~T[10:30:00]
        })

      {:ok, _} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Overlapping second",
          start_time: ~T[10:00:00],
          end_time: ~T[11:00:00]
        })

      html = render_agenda(agenda, event)

      assert html =~ "Chronological Warning"
    end

    test "ignores items without a start time when checking order", %{
      agenda: agenda,
      event: event
    } do
      {:ok, _} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Untimed"
        })

      {:ok, _} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Timed",
          start_time: ~T[09:00:00]
        })

      html = render_agenda(agenda, event)

      refute html =~ "Chronological Warning"
    end
  end

  describe "styling and layout" do
    test "applies correct CSS classes for agenda items", %{
      agenda: agenda,
      event: event
    } do
      {:ok, _item} =
        Agendas.create_agenda_item(event.id, agenda, %{
          title: "Test"
        })

      agenda = Agendas.get_agenda!(agenda.id)

      html =
        render_component(AgendaEditComponent, %{
          id: "agenda-edit-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "bg-blue-100"
      assert html =~ "drag-handle"
    end

    test "uses timeline layout for agenda items", %{
      agenda: agenda,
      event: event
    } do
      agenda = Agendas.get_agenda!(agenda.id)

      html =
        render_component(AgendaEditComponent, %{
          id: "agenda-edit-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "space-y-4"
      assert html =~ "left-[15px]"
    end
  end

  defp render_agenda(agenda, event) do
    agenda = Agendas.get_agenda!(agenda.id)

    render_component(AgendaEditComponent, %{
      id: "agenda-edit-#{agenda.id}",
      agenda: agenda,
      agenda_id: agenda.id,
      event_id: event.id
    })
  end
end
