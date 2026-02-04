defmodule YscWeb.AgendasLive.FormComponentTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.EventsFixtures

  alias Ysc.Agendas
  alias YscWeb.AgendasLive.FormComponent

  setup do
    event = event_fixture()
    {:ok, agenda} = Agendas.create_agenda(event, %{title: "Test Agenda"})
    %{event: event, agenda: agenda}
  end

  describe "rendering" do
    test "displays agenda title form", %{agenda: agenda, event: event} do
      html =
        render_component(FormComponent, %{
          id: "agenda-form-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "Agenda Title"
      assert html =~ "Test Agenda"
    end

    test "renders input field for title", %{agenda: agenda, event: event} do
      html =
        render_component(FormComponent, %{
          id: "agenda-form-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "type=\"text\""
      assert html =~ "value=\"Test Agenda\""
    end

    test "form has correct phx-target", %{agenda: agenda, event: event} do
      html =
        render_component(FormComponent, %{
          id: "agenda-form-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "phx-target"
      assert html =~ "phx-change=\"validate\""
      assert html =~ "phx-submit=\"save\""
    end

    test "renders form with agenda ID", %{agenda: agenda, event: event} do
      html =
        render_component(FormComponent, %{
          id: "agenda-form-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      assert html =~ "agenda-title-form-#{agenda.id}"
    end
  end

  describe "update" do
    test "initializes with agenda data", %{agenda: agenda, event: event} do
      html =
        render_component(FormComponent, %{
          id: "agenda-form-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      # Should display agenda title in form
      assert html =~ "Test Agenda"
    end

    test "displays form for agenda with different title", %{event: event} do
      {:ok, agenda} = Agendas.create_agenda(event, %{title: "Custom Title"})

      html =
        render_component(FormComponent, %{
          id: "agenda-form-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      # Form should render with custom title
      assert html =~ "Custom Title"
    end
  end

  describe "auto-submit on blur" do
    test "form submits on blur event", %{agenda: agenda, event: event} do
      html =
        render_component(FormComponent, %{
          id: "agenda-form-#{agenda.id}",
          agenda: agenda,
          agenda_id: agenda.id,
          event_id: event.id
        })

      # Should have blur handler that dispatches submit
      assert html =~ "phx-blur"
      assert html =~ "submit"
    end
  end
end
