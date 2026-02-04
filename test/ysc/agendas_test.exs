defmodule Ysc.AgendasTest do
  @moduledoc """
  Tests for the Ysc.Agendas context module.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias Ysc.Agendas
  alias Ysc.Events
  alias Ysc.Events.{Agenda, AgendaItem}

  setup do
    organizer = user_fixture()

    {:ok, event} =
      Events.create_event(%{
        title: "Test Event",
        description: "A test event",
        state: "draft",
        organizer_id: organizer.id,
        start_date:
          DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), 30, :day)
      })

    %{event: event, organizer: organizer}
  end

  describe "create_agenda/2" do
    test "creates an agenda for an event", %{event: event} do
      assert {:ok, %Agenda{} = agenda} =
               Agendas.create_agenda(event, %{title: "Day 1"})

      assert agenda.title == "Day 1"
      assert agenda.event_id == event.id
      assert agenda.position == 0
    end

    test "creates multiple agendas with correct positions", %{event: event} do
      {:ok, agenda1} = Agendas.create_agenda(event, %{title: "Day 1"})
      {:ok, agenda2} = Agendas.create_agenda(event, %{title: "Day 2"})
      {:ok, agenda3} = Agendas.create_agenda(event, %{title: "Day 3"})

      assert agenda1.position == 0
      assert agenda2.position == 1
      assert agenda3.position == 2
    end
  end

  describe "get_agenda!/1" do
    test "returns the agenda with preloaded items", %{event: event} do
      {:ok, agenda} = Agendas.create_agenda(event, %{title: "Day 1"})

      {:ok, _item} =
        Agendas.create_agenda_item(event.id, agenda, %{title: "Opening"})

      fetched = Agendas.get_agenda!(agenda.id)
      assert fetched.id == agenda.id
      assert length(fetched.agenda_items) == 1
    end

    test "raises when agenda doesn't exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Agendas.get_agenda!(Ecto.ULID.generate())
      end
    end
  end

  describe "list_agendas_for_event/1" do
    test "returns all agendas for an event ordered by position", %{event: event} do
      {:ok, _} = Agendas.create_agenda(event, %{title: "Day 1"})
      {:ok, _} = Agendas.create_agenda(event, %{title: "Day 2"})

      agendas = Agendas.list_agendas_for_event(event.id)
      assert length(agendas) == 2
      assert Enum.at(agendas, 0).title == "Day 1"
      assert Enum.at(agendas, 1).title == "Day 2"
    end

    test "returns empty list when event has no agendas", %{event: event} do
      assert Agendas.list_agendas_for_event(event.id) == []
    end
  end

  describe "update_agenda/3" do
    test "updates an agenda's title", %{event: event} do
      {:ok, agenda} = Agendas.create_agenda(event, %{title: "Day 1"})

      {:ok, updated} =
        Agendas.update_agenda(event.id, agenda, %{title: "Day One"})

      assert updated.title == "Day One"
    end
  end

  describe "delete_agenda/2" do
    test "deletes an agenda", %{event: event} do
      {:ok, agenda} = Agendas.create_agenda(event, %{title: "Day 1"})

      {:ok, _} = Agendas.delete_agenda(event, agenda)
      assert Agendas.list_agendas_for_event(event.id) == []
    end
  end

  describe "create_agenda_item/3" do
    test "creates an agenda item", %{event: event} do
      {:ok, agenda} = Agendas.create_agenda(event, %{title: "Day 1"})

      assert {:ok, %AgendaItem{} = item} =
               Agendas.create_agenda_item(event.id, agenda, %{
                 title: "Opening Ceremony"
               })

      assert item.title == "Opening Ceremony"
      assert item.agenda_id == agenda.id
      assert item.position == 0
    end

    test "creates multiple items with correct positions", %{event: event} do
      {:ok, agenda} = Agendas.create_agenda(event, %{title: "Day 1"})

      {:ok, item1} =
        Agendas.create_agenda_item(event.id, agenda, %{title: "Item 1"})

      {:ok, item2} =
        Agendas.create_agenda_item(event.id, agenda, %{title: "Item 2"})

      {:ok, item3} =
        Agendas.create_agenda_item(event.id, agenda, %{title: "Item 3"})

      assert item1.position == 0
      assert item2.position == 1
      assert item3.position == 2
    end
  end

  describe "get_agenda_item!/1" do
    test "returns the agenda item with preloaded agenda", %{event: event} do
      {:ok, agenda} = Agendas.create_agenda(event, %{title: "Day 1"})

      {:ok, item} =
        Agendas.create_agenda_item(event.id, agenda, %{title: "Opening"})

      fetched = Agendas.get_agenda_item!(item.id)
      assert fetched.id == item.id
      assert fetched.agenda.id == agenda.id
    end
  end

  describe "update_agenda_item/3" do
    test "updates an agenda item's title", %{event: event} do
      {:ok, agenda} = Agendas.create_agenda(event, %{title: "Day 1"})

      {:ok, item} =
        Agendas.create_agenda_item(event.id, agenda, %{title: "Opening"})

      {:ok, updated} =
        Agendas.update_agenda_item(event.id, item, %{title: "Grand Opening"})

      assert updated.title == "Grand Opening"
    end
  end

  describe "delete_agenda_item/2" do
    test "deletes an agenda item", %{event: event} do
      {:ok, agenda} = Agendas.create_agenda(event, %{title: "Day 1"})

      {:ok, item} =
        Agendas.create_agenda_item(event.id, agenda, %{title: "Opening"})

      {:ok, _} = Agendas.delete_agenda_item(event.id, item)

      updated_agenda = Agendas.get_agenda!(agenda.id)
      assert updated_agenda.agenda_items == []
    end
  end

  describe "change_agenda/2" do
    test "returns a changeset for an agenda", %{event: event} do
      {:ok, agenda} = Agendas.create_agenda(event, %{title: "Day 1"})
      changeset = Agendas.change_agenda(agenda, %{title: "New Title"})

      assert %Ecto.Changeset{} = changeset
      assert changeset.changes.title == "New Title"
    end
  end

  describe "change_agenda_item/2" do
    test "returns a changeset for an agenda item", %{event: event} do
      {:ok, agenda} = Agendas.create_agenda(event, %{title: "Day 1"})

      {:ok, item} =
        Agendas.create_agenda_item(event.id, agenda, %{title: "Opening"})

      changeset = Agendas.change_agenda_item(item, %{title: "New Title"})
      assert %Ecto.Changeset{} = changeset
      assert changeset.changes.title == "New Title"
    end
  end

  describe "list_all_agenda_items/0" do
    test "returns all agenda items", %{event: event} do
      {:ok, agenda} = Agendas.create_agenda(event, %{title: "Day 1"})

      {:ok, _item1} =
        Agendas.create_agenda_item(event.id, agenda, %{title: "Item 1"})

      {:ok, _item2} =
        Agendas.create_agenda_item(event.id, agenda, %{title: "Item 2"})

      items = Agendas.list_all_agenda_items()
      assert length(items) >= 2
    end
  end

  describe "update_agenda_position/3" do
    test "updates agenda position", %{event: event} do
      {:ok, agenda1} = Agendas.create_agenda(event, %{title: "Day 1"})
      {:ok, _agenda2} = Agendas.create_agenda(event, %{title: "Day 2"})

      assert :ok = Agendas.update_agenda_position(event.id, agenda1, 1)
      # Reload to verify
      updated = Agendas.get_agenda!(agenda1.id)
      assert updated.position == 1
    end
  end

  describe "update_agenda_item_position/3" do
    test "updates agenda item position", %{event: event} do
      {:ok, agenda} = Agendas.create_agenda(event, %{title: "Day 1"})

      {:ok, item1} =
        Agendas.create_agenda_item(event.id, agenda, %{title: "Item 1"})

      {:ok, _item2} =
        Agendas.create_agenda_item(event.id, agenda, %{title: "Item 2"})

      assert :ok = Agendas.update_agenda_item_position(event.id, item1, 1)
      # Reload to verify
      updated = Agendas.get_agenda_item!(item1.id)
      assert updated.position == 1
    end
  end

  describe "move_agenda_item_to_agenda/4" do
    test "moves agenda item to different agenda", %{event: event} do
      {:ok, agenda1} = Agendas.create_agenda(event, %{title: "Day 1"})
      {:ok, agenda2} = Agendas.create_agenda(event, %{title: "Day 2"})

      {:ok, item} =
        Agendas.create_agenda_item(event.id, agenda1, %{title: "Item"})

      assert :ok =
               Agendas.move_agenda_item_to_agenda(event.id, item, agenda2, 0)

      # Reload to verify
      updated = Agendas.get_agenda_item!(item.id)
      assert updated.agenda_id == agenda2.id
    end
  end
end
