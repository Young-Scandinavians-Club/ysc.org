defmodule Ysc.Agendas do
  @moduledoc """
  Context module for managing event agendas and agenda items.

  Provides functions for creating, updating, and organizing agenda items for events.
  """
  alias Ysc.Events.AgendaItem
  alias Ysc.Events.Agenda

  import Ecto.Query, warn: false
  alias Ysc.Repo

  def subscribe(event_id) do
    Phoenix.PubSub.subscribe(Ysc.PubSub, topic(event_id))
  end

  def get_agenda_item!(id) do
    Repo.get!(AgendaItem, id) |> Repo.preload(:agenda)
  end

  def list_all_agenda_items do
    Repo.all(AgendaItem)
  end

  def get_agenda!(id) do
    Repo.get!(Agenda, id) |> Repo.preload(:agenda_items)
  end

  def list_agendas_for_event(event_id) do
    Repo.all(
      from a in Agenda,
        where: a.event_id == ^event_id,
        preload: [:agenda_items],
        order_by: [asc: a.position]
    )
  end

  def delete_agenda(event, agenda) do
    Repo.delete(agenda)
    |> case do
      {:ok, _} ->
        broadcast(event.id, %Ysc.MessagePassingEvents.AgendaDeleted{
          agenda: agenda
        })

        {:ok, agenda}

      {:error, _} ->
        {:error, agenda}
    end
  end

  def delete_agenda_item(event_id, agenda_item) do
    Repo.delete(agenda_item)
    |> case do
      {:ok, _} ->
        broadcast(event_id, %Ysc.MessagePassingEvents.AgendaItemDeleted{
          agenda_item: agenda_item
        })

        {:ok, agenda_item}

      {:error, _} ->
        {:error, agenda_item}
    end
  end

  def update_agenda_position(event_id, agenda, new_index) do
    %Agenda{} = agenda

    Ecto.Multi.new()
    |> multi_reposition(:new, agenda, agenda, new_index, event_id: event_id)
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        new_agenda = %{agenda | position: new_index}

        broadcast(event_id, %Ysc.MessagePassingEvents.AgendaRepositioned{
          agenda: new_agenda
        })

        :ok

      {:error, _failed_op, failed_val, _changes_so_far} ->
        {:error, failed_val}
    end
  end

  def update_agenda_item_position(event_id, agenda_item, new_index) do
    %AgendaItem{} = agenda_item

    Ecto.Multi.new()
    |> multi_reposition(
      :new,
      agenda_item,
      {Agenda, agenda_item.agenda_id},
      new_index,
      agenda_id: agenda_item.agenda_id
    )
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        new_agenda_item = %{agenda_item | position: new_index}

        broadcast(event_id, %Ysc.MessagePassingEvents.AgendaItemRepositioned{
          agenda_item: new_agenda_item
        })

        :ok

      {:error, _failed_op, failed_val, _changes_so_far} ->
        {:error, failed_val}
    end
  end

  def move_agenda_item_to_agenda(event_id, agenda_item, agenda, at_index) do
    %AgendaItem{} = agenda_item

    Ecto.Multi.new()
    |> multi_update_all(:dec_positions, fn _ ->
      from(a in AgendaItem,
        where: a.agenda_id == ^agenda.id,
        where:
          a.position >
            subquery(
              from og in AgendaItem,
                where: og.id == ^agenda_item.id,
                select: og.position
            ),
        update: [inc: [position: -1]]
      )
    end)
    |> Ecto.Multi.run(:pos_at_end, fn repo, _changes ->
      position =
        repo.one(
          from(a in AgendaItem,
            where: a.agenda_id == ^agenda.id,
            select: count(a.id)
          )
        )

      {:ok, position}
    end)
    |> multi_update_all(:move_to_agenda, fn %{pos_at_end: pos_at_end} ->
      from(a in AgendaItem,
        where: a.id == ^agenda_item.id,
        update: [set: [agenda_id: ^agenda.id, position: ^pos_at_end]]
      )
    end)
    |> multi_reposition(:new, agenda_item, agenda, at_index,
      agenda_id: agenda.id
    )
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        new_agenda_item = %{
          agenda_item
          | agenda: agenda,
            agenda_id: agenda.id,
            position: at_index
        }

        broadcast(event_id, %Ysc.MessagePassingEvents.AgendaItemDeleted{
          agenda_item: agenda_item
        })

        broadcast(event_id, %Ysc.MessagePassingEvents.AgendaItemRepositioned{
          agenda_item: new_agenda_item
        })

        :ok

      {:error, _failed_op, failed_val, _changes_so_far} ->
        {:error, failed_val}
    end
  end

  def update_agenda_item(event_id, agenda_item, params) do
    agenda_item
    |> AgendaItem.changeset(params)
    |> Repo.update()
    |> case do
      {:ok, agenda_item} ->
        broadcast(event_id, %Ysc.MessagePassingEvents.AgendaItemUpdated{
          agenda_item: agenda_item
        })

        {:ok, agenda_item}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update_agenda(event_id, agenda, params) do
    agenda
    |> Agenda.changeset(params)
    |> Repo.update()
    |> case do
      {:ok, agenda} ->
        broadcast(event_id, %Ysc.MessagePassingEvents.AgendaUpdated{
          agenda: agenda
        })

        {:ok, agenda}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def change_agenda_item(agenda_item_or_changeset, attrs \\ %{}) do
    AgendaItem.changeset(agenda_item_or_changeset, attrs)
  end

  def create_agenda_item(event_id, agenda, attrs \\ %{}) do
    changeset = AgendaItem.changeset(%AgendaItem{agenda_id: agenda.id}, attrs)

    Ecto.Multi.new()
    |> Ecto.Multi.run(:position, fn repo, _changes ->
      position =
        repo.one(
          from(a in AgendaItem,
            where: a.agenda_id == ^agenda.id,
            select: count(a.id)
          )
        )

      {:ok, position}
    end)
    |> Ecto.Multi.insert(:agenda_item, fn %{position: position} ->
      changeset
      |> Ecto.Changeset.put_change(:position, position)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{agenda_item: agenda_item}} ->
        broadcast(event_id, %Ysc.MessagePassingEvents.AgendaItemAdded{
          agenda_item: agenda_item
        })

        {:ok, agenda_item}

      {:error, _failed_op, failed_val, _changes_so_far} ->
        {:error, failed_val}
    end
  end

  def change_agenda(%Agenda{} = agenda, attrs \\ %{}) do
    Agenda.changeset(agenda, attrs)
  end

  def create_agenda(event, attrs \\ %{}) do
    changeset = Agenda.changeset(%Agenda{event_id: event.id}, attrs)

    Ecto.Multi.new()
    |> Ecto.Multi.run(:position, fn repo, _changes ->
      position =
        repo.one(
          from(a in Agenda,
            where: a.event_id == ^event.id,
            select: count(a.id)
          )
        )

      {:ok, position}
    end)
    |> Ecto.Multi.insert(:agenda, fn %{position: position} ->
      changeset
      |> Ecto.Changeset.put_change(:position, position)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{agenda: agenda}} ->
        agenda = Repo.preload(agenda, :agenda_items)

        broadcast(event.id, %Ysc.MessagePassingEvents.AgendaAdded{
          agenda: agenda
        })

        {:ok, agenda}

      {:error, _failed_op, failed_val, _changes_so_far} ->
        {:error, failed_val}
    end
  end

  defp multi_update_all(multi, name, func, opts \\ []) do
    Ecto.Multi.update_all(multi, name, func, opts)
  end

  defp multi_reposition(
         %Ecto.Multi{} = multi,
         name,
         %type{} = struct,
         _lock,
         new_idx,
         where_query
       )
       when is_integer(new_idx) do
    old_position =
      from(og in type, where: og.id == ^struct.id, select: og.position)

    multi
    |> Ecto.Multi.run({:index, name}, fn repo, _changes ->
      # Build query with where conditions from keyword list
      # Handle common cases: event_id and agenda_id
      base_query = from(t in type, select: count(t.id))

      query =
        case where_query do
          [event_id: event_id] ->
            from(t in base_query, where: t.event_id == ^event_id)

          [agenda_id: agenda_id] ->
            from(t in base_query, where: t.agenda_id == ^agenda_id)

          _ ->
            base_query
        end

      case repo.one(query) do
        count when new_idx < count -> {:ok, new_idx}
        count -> {:ok, count - 1}
      end
    end)
    |> multi_update_all({:dec_positions, name}, fn %{
                                                     {:index, ^name} =>
                                                       computed_index
                                                   } ->
      # Build query with where conditions from keyword list
      # Handle common cases: event_id and agenda_id
      base_query =
        from(t in type,
          where: t.id != ^struct.id,
          where:
            t.position > subquery(old_position) and
              t.position <= ^computed_index,
          update: [inc: [position: -1]]
        )

      case where_query do
        [event_id: event_id] ->
          from(t in base_query, where: t.event_id == ^event_id)

        [agenda_id: agenda_id] ->
          from(t in base_query, where: t.agenda_id == ^agenda_id)

        _ ->
          base_query
      end
    end)
    |> multi_update_all({:inc_positions, name}, fn %{
                                                     {:index, ^name} =>
                                                       computed_index
                                                   } ->
      # Build query with where conditions from keyword list
      # Handle common cases: event_id and agenda_id
      base_query =
        from(t in type,
          where: t.id != ^struct.id,
          where:
            t.position < subquery(old_position) and
              t.position >= ^computed_index,
          update: [inc: [position: 1]]
        )

      case where_query do
        [event_id: event_id] ->
          from(t in base_query, where: t.event_id == ^event_id)

        [agenda_id: agenda_id] ->
          from(t in base_query, where: t.agenda_id == ^agenda_id)

        _ ->
          base_query
      end
    end)
    |> multi_update_all({:position, name}, fn %{
                                                {:index, ^name} =>
                                                  computed_index
                                              } ->
      from(t in type,
        where: t.id == ^struct.id,
        update: [set: [position: ^computed_index]]
      )
    end)
  end

  defp topic(event_id) do
    "agendas:#{event_id}"
  end

  defp broadcast(event_id, event) do
    Phoenix.PubSub.broadcast(Ysc.PubSub, topic(event_id), {__MODULE__, event})
  end
end
