defmodule YscWeb.AgendaEditComponent do
  @moduledoc """
  LiveView component for editing event agendas.

  Provides an interface for admins to create and edit agenda items for events.
  """
  use YscWeb, :live_component

  alias Ysc.Events.AgendaItem

  alias Ysc.Agendas

  def render(assigns) do
    ~H"""
    <div>
      <div
        id={"agenda-#{@agenda_id}"}
        phx-update="stream"
        phx-hook="Sortable"
        class="grid grid-cols-1 gap-2"
        data-group="agenda"
        data-agenda_id={@agenda_id}
      >
        <div
          :for={{id, form} <- @streams.agenda_items}
          id={id}
          data-id={form.data.id}
          data-agenda_id={form.data.agenda_id}
          class="
          relative flex items-center space-x-2 rounded px-2 py-4
          focus-within:ring-2 focus-within:ring-indigo-500 focus-within:ring-offset-2 hover:border-zinc-100
          drag-item:focus-within:ring-0 drag-item:focus-within:ring-offset-0
          drag-ghost:bg-zinc-300 drag-ghost:border-0 drag-ghost:ring-0 drag-item:shadow-lg
          bg-blue-100
          "
        >
          <div class="drag-handle hover:cursor-row-resize group h-full flex items-center">
            <.icon
              name="hero-arrows-up-down"
              class="group-hover:bg-zinc-800 bg-zinc-500 transition"
            />
          </div>

          <.form
            :let={_f}
            for={form}
            as={nil}
            phx-change="validate"
            phx-submit="save"
            phx-value-id={form.data.id}
            phx-target={@myself}
            class="min-w-0 flex-1 py-2 drag-ghost:opacity-0 border-l pl-4 border-l-2 border-blue-300"
          >
            <div class="w-full">
              <div class="flex space-x-1">
                <div class="flex-auto space-y-4">
                  <.input
                    type="text"
                    field={form[:title]}
                    placeholder="Title"
                    label="Title"
                    phx-mounted={!form.data.id && JS.focus()}
                    phx-keydown={
                      !form.data.id && JS.push("discard", target: @myself)
                    }
                    phx-key="escape"
                    phx-blur={JS.dispatch("submit", to: "##{form.id}")}
                    phx-target={@myself}
                  />

                  <div class="flex flex-row space-x-3">
                    <.input
                      type="time"
                      field={form[:start_time]}
                      label="Start"
                      phx-key="escape"
                      phx-keydown={
                        !form.data.id && JS.push("discard", target: @myself)
                      }
                      phx-blur={
                        form.data.id && JS.dispatch("submit", to: "##{form.id}")
                      }
                      phx-target={@myself}
                    />

                    <.input
                      type="time"
                      field={form[:end_time]}
                      label="End"
                      phx-keydown={
                        !form.data.id && JS.push("discard", target: @myself)
                      }
                      phx-key="escape"
                      phx-blur={
                        form.data.id && JS.dispatch("submit", to: "##{form.id}")
                      }
                      phx-target={@myself}
                    />
                  </div>
                </div>

                <div class="px-2 items-center flex">
                  <button
                    type="button"
                    phx-click={
                      JS.push("delete", target: @myself, value: %{id: form.data.id})
                      |> hide("##{id}")
                    }
                    class="group rounded"
                  >
                    <.icon
                      class="group-hover:bg-red-400 bg-zinc-800 transition"
                      name="hero-trash"
                    />
                  </button>
                </div>
              </div>
            </div>
          </.form>
        </div>
      </div>
      <.button
        phx-click={
          JS.push("new", value: %{at: -1, agenda_id: @agenda_id}, target: @myself)
        }
        class="mt-4"
      >
        Add Slot
      </.button>
    </div>
    """
  end

  def update(
        %{
          event: %Ysc.MessagePassingEvents.AgendaItemAdded{
            agenda_item: agenda_item
          }
        },
        socket
      ) do
    {:ok,
     stream_insert(socket, :agenda_items, to_change_form(agenda_item, %{}))}
  end

  def update(
        %{
          event: %Ysc.MessagePassingEvents.AgendaItemDeleted{
            agenda_item: agenda_item
          }
        },
        socket
      ) do
    {:ok,
     stream_delete(socket, :agenda_items, to_change_form(agenda_item, %{}))}
  end

  def update(
        %{
          event: %Ysc.MessagePassingEvents.AgendaItemUpdated{
            agenda_item: agenda_item
          }
        },
        socket
      ) do
    {:ok,
     stream_insert(socket, :agenda_items, to_change_form(agenda_item, %{}))}
  end

  def update(
        %{
          event: %Ysc.MessagePassingEvents.AgendaItemRepositioned{
            agenda_item: agenda_item
          }
        },
        socket
      ) do
    {:ok,
     stream_insert(socket, :agenda_items, to_change_form(agenda_item, %{}),
       at: agenda_item.position
     )}
  end

  def update(%{agenda: agenda} = _assigns, socket) do
    agenda_forms = Enum.map(agenda.agenda_items, &to_change_form(&1, %{}))

    {:ok,
     socket
     |> assign(agenda_id: agenda.id)
     |> stream(:agenda_items, agenda_forms)}
  end

  def handle_event(
        "validate",
        %{"agenda_item" => agenda_item_params} = params,
        socket
      ) do
    agenda_item = %AgendaItem{
      id: params["id"],
      agenda_id: socket.assigns[:agenda_id]
    }

    {:noreply,
     stream_insert(
       socket,
       :agenda_items,
       to_change_form(agenda_item, agenda_item_params, :validate)
     )}
  end

  def handle_event("save", %{"id" => id, "agenda_item" => params}, socket) do
    agenda_item = Agendas.get_agenda_item!(id)

    case Agendas.update_agenda_item(
           agenda_item.agenda.event_id,
           agenda_item,
           params
         ) do
      {:ok, _updated_agenda_item} ->
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         stream_insert(
           socket,
           :agenda_items,
           to_change_form(changeset, %{}, :insert)
         )}
    end
  end

  def handle_event("save", %{"agenda_item" => params}, socket) do
    agenda = Agendas.get_agenda!(socket.assigns.agenda_id)

    case Agendas.create_agenda_item(agenda.event_id, agenda, params) do
      {:ok, _new_agenda_item} ->
        empty_form =
          to_change_form(build_agenda_item(socket.assigns.agenda_id), %{})

        {
          :noreply,
          socket |> stream_delete(:agenda_items, empty_form)
        }

      {:error, changeset} ->
        {:noreply,
         stream_insert(
           socket,
           :agenda_items,
           to_change_form(changeset, %{}, :insert)
         )}
    end
  end

  def handle_event("delete", %{"id" => nil}, socket) do
    empty_form =
      to_change_form(build_agenda_item(socket.assigns.agenda_id), %{})

    {:noreply, socket |> stream_delete(:agenda_items, empty_form)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    agenda_item = Agendas.get_agenda_item!(id)

    {:ok, _} =
      Agendas.delete_agenda_item(agenda_item.agenda.event_id, agenda_item)

    {:noreply, socket}
  end

  def handle_event("new", %{"at" => at}, socket) do
    agenda_item = build_agenda_item(socket.assigns.agenda_id)

    {:noreply,
     stream_insert(socket, :agenda_items, to_change_form(agenda_item, %{}),
       at: at
     )}
  end

  def handle_event(
        "reposition",
        %{"id" => id, "new" => new_idx, "old" => _} = params,
        socket
      ) do
    if Map.has_key?(params, "to") and is_map(params["to"]) do
      new_agenda_id = params["to"]["agenda_id"]
      agenda_item = Agendas.get_agenda_item!(id)
      agenda = Agendas.get_agenda!(new_agenda_id)

      Agendas.move_agenda_item_to_agenda(
        agenda.event_id,
        agenda_item,
        agenda,
        new_idx
      )

      {:noreply, socket}
    else
      agenda_item = Agendas.get_agenda_item!(id)

      Agendas.update_agenda_item_position(
        agenda_item.agenda.event_id,
        agenda_item,
        new_idx
      )

      {:noreply, socket}
    end
  end

  def handle_event("restore_if_unsaved", %{"value" => val} = params, socket) do
    id = params["id"]
    agenda_item = Agendas.get_agenda_item!(id)

    if agenda_item.title == val do
      {:noreply, socket}
    else
      {:noreply,
       stream_insert(socket, :agenda_items, to_change_form(agenda_item, %{}))}
    end
  end

  defp to_change_form(agenda_item_or_changeset, params, action \\ nil) do
    changeset =
      agenda_item_or_changeset
      |> Agendas.change_agenda_item(params)
      |> Map.put(:action, action)

    to_form(changeset,
      as: "agenda_item",
      id: "form-#{changeset.data.agenda_id}-#{changeset.data.id}"
    )
  end

  defp build_agenda_item(agenda_id), do: %AgendaItem{agenda_id: agenda_id}
end
