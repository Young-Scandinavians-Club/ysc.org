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
        :if={@chronological_warning}
        class="relative z-10 mb-4 rounded-md bg-amber-50 p-3 border border-amber-200"
      >
        <div class="flex">
          <div class="flex-shrink-0">
            <.icon name="hero-exclamation-triangle" class="h-5 w-5 text-amber-400" />
          </div>
          <div class="ml-3">
            <h3 class="text-sm font-medium text-amber-800">
              Chronological Warning
            </h3>
            <div class="mt-1 text-sm text-amber-700">
              <p>Some items in this agenda appear to be out of order.</p>
            </div>
          </div>
        </div>
      </div>

      <div class="relative">
        <div
          class="absolute left-[15px] top-0 bottom-8 w-px bg-zinc-200"
          aria-hidden="true"
        />

        <div
          id={"agenda-#{@agenda_id}"}
          phx-update="stream"
          phx-hook="Sortable"
          class="space-y-4"
          data-group="agenda"
          data-agenda_id={@agenda_id}
        >
          <div
            :for={{id, form} <- @streams.agenda_items}
            id={id}
            data-id={form.data.id}
            data-agenda_id={form.data.agenda_id}
            class="relative pl-8 group drag-item:scale-[1.02] drag-item:shadow-xl drag-item:z-10 drag-item:opacity-100 drag-ghost:opacity-100 drag-ghost:bg-blue-50 drag-ghost:border-2 drag-ghost:border-dashed drag-ghost:border-blue-400 drag-ghost:rounded-xl"
          >
            <!-- Timeline Dot -->
            <div class="absolute left-[8px] top-5 w-3.5 h-3.5 rounded-full border-[3px] border-white bg-zinc-300 z-10 transition-colors group-focus-within:bg-blue-600 group-focus-within:border-blue-100 drag-ghost:opacity-0">
            </div>

            <.form
              :let={_f}
              for={form}
              as={nil}
              phx-change="validate"
              phx-debounce="300"
              phx-submit="save"
              phx-value-id={form.data.id}
              phx-target={@myself}
              class="relative flex flex-col sm:flex-row sm:items-start gap-3 p-3 -mx-3 rounded-xl border border-transparent hover:bg-zinc-50 hover:border-zinc-200 focus-within:bg-white focus-within:border-blue-200 focus-within:shadow-sm transition-all group/form drag-ghost:opacity-0"
            >
              <!-- Drag Handle (Appears on hover) -->
              <div class="absolute -left-9 top-4 text-zinc-300 hover:text-zinc-600 cursor-grab active:cursor-grabbing opacity-0 group-hover:opacity-100 transition-opacity drag-handle bg-white rounded">
                <.icon name="hero-arrows-up-down" class="w-5 h-5 block" />
              </div>

              <!-- Time Inputs (Styled as the blue pill) -->
              <div class="w-full sm:w-52 flex-shrink-0">
                <div class="grid grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] items-center gap-0.5 bg-blue-50 focus-within:bg-white focus-within:ring-2 focus-within:ring-blue-500 px-2 py-1 rounded transition-all overflow-hidden">
                  <input
                    type="time"
                    name={form[:start_time].name}
                    value={
                      Phoenix.HTML.Form.normalize_value(
                        "time",
                        form[:start_time].value
                      )
                    }
                    class="min-w-0 w-full text-[11px] font-bold text-blue-600 bg-transparent border-none p-0 text-center focus:ring-0"
                    phx-keydown={
                      !form.data.id && JS.push("discard", target: @myself)
                    }
                    phx-key="escape"
                    phx-blur={
                      form.data.id && JS.dispatch("submit", to: "##{form.id}")
                    }
                  />
                  <span class="text-blue-300 text-[10px] font-bold px-0.5">-</span>
                  <input
                    type="time"
                    name={form[:end_time].name}
                    value={
                      Phoenix.HTML.Form.normalize_value(
                        "time",
                        form[:end_time].value
                      )
                    }
                    class="min-w-0 w-full text-[11px] font-bold text-blue-600 bg-transparent border-none p-0 text-center focus:ring-0"
                    phx-keydown={
                      !form.data.id && JS.push("discard", target: @myself)
                    }
                    phx-key="escape"
                    phx-blur={
                      form.data.id && JS.dispatch("submit", to: "##{form.id}")
                    }
                  />
                </div>

                <% warning =
                  time_warning(form[:start_time].value, form[:end_time].value) %>
                <p
                  :if={warning}
                  class="text-amber-600 text-xs mt-1 flex items-center"
                >
                  <.icon name="hero-exclamation-triangle" class="w-3.5 h-3.5 mr-1" />
                  {warning}
                </p>
              </div>

              <!-- Content Inputs -->
              <div class="flex-1 min-w-0 pr-8">
                <!-- Title -->
                <textarea
                  id={"#{form.id}-title"}
                  name={form[:title].name}
                  rows="1"
                  phx-hook="AutoResizeTextarea"
                  class="block w-full text-lg font-black text-zinc-900 tracking-tight leading-tight bg-transparent border-none p-0 focus:ring-0 placeholder:text-zinc-300 transition-colors focus:text-blue-600 resize-none overflow-hidden whitespace-pre-wrap break-words"
                  placeholder="Agenda Item Title"
                  phx-mounted={!form.data.id && JS.focus()}
                  phx-keydown={!form.data.id && JS.push("discard", target: @myself)}
                  phx-key="escape"
                  phx-blur={JS.dispatch("submit", to: "##{form.id}")}
                >{form[:title].value}</textarea>

                <!-- Description -->
                <textarea
                  id={"#{form.id}-description"}
                  name={form[:description].name}
                  rows="1"
                  phx-hook="AutoResizeTextarea"
                  class="block w-full text-sm text-zinc-500 font-normal mt-2 leading-relaxed bg-transparent border-none p-0 focus:ring-0 placeholder:text-zinc-300 resize-none overflow-hidden whitespace-pre-wrap break-words"
                  placeholder="Add a description... (optional)"
                  phx-keydown={!form.data.id && JS.push("discard", target: @myself)}
                  phx-key="escape"
                  phx-blur={JS.dispatch("submit", to: "##{form.id}")}
                >{form[:description].value}</textarea>
              </div>

              <!-- Delete Action -->
              <button
                type="button"
                title="Delete slot"
                phx-click={
                  JS.push("delete", target: @myself, value: %{id: form.data.id})
                  |> hide("##{id}")
                }
                class="absolute top-3 right-3 opacity-0 group-hover/form:opacity-100 text-zinc-400 hover:text-red-500 transition-all bg-white hover:bg-red-50 rounded p-1.5 shadow-sm border border-zinc-200"
              >
                <.icon name="hero-trash" class="w-4 h-4 block" />
              </button>
            </.form>
          </div>
        </div>

        <!-- Add Slot Button (styled to sit on the timeline) -->
        <div class="relative pl-8 mt-4 pt-2 group drag-ghost:opacity-0">
          <div class="absolute left-[8px] top-4 w-3.5 h-3.5 rounded-full border-[3px] border-white bg-blue-100 z-10 transition-colors group-hover:bg-blue-600">
          </div>
          <button
            type="button"
            class="w-full flex items-center justify-start gap-2 py-2 px-3 text-sm font-semibold text-blue-600 hover:text-blue-700 bg-blue-50/50 hover:bg-blue-50 rounded-lg transition"
            phx-click={
              JS.push("new",
                value: %{at: -1, agenda_id: @agenda_id},
                target: @myself
              )
            }
          >
            <.icon name="hero-plus" class="w-4 h-4" /> Add Timeline Slot
          </button>
        </div>
      </div>
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
    items = upsert_agenda_item(socket.assigns.agenda_items, agenda_item)

    {:ok,
     socket
     |> assign(:agenda_items, items)
     |> assign(:chronological_warning, check_chronological_order(items))
     |> stream_insert(:agenda_items, to_change_form(agenda_item, %{}))}
  end

  def update(
        %{
          event: %Ysc.MessagePassingEvents.AgendaItemDeleted{
            agenda_item: agenda_item
          }
        },
        socket
      ) do
    items = remove_agenda_item(socket.assigns.agenda_items, agenda_item)

    {:ok,
     socket
     |> assign(:agenda_items, items)
     |> assign(:chronological_warning, check_chronological_order(items))
     |> stream_delete(:agenda_items, to_change_form(agenda_item, %{}))}
  end

  def update(
        %{
          event: %Ysc.MessagePassingEvents.AgendaItemUpdated{
            agenda_item: agenda_item
          }
        },
        socket
      ) do
    items = upsert_agenda_item(socket.assigns.agenda_items, agenda_item)

    {:ok,
     socket
     |> assign(:agenda_items, items)
     |> assign(:chronological_warning, check_chronological_order(items))
     |> stream_insert(:agenda_items, to_change_form(agenda_item, %{}))}
  end

  def update(
        %{
          event: %Ysc.MessagePassingEvents.AgendaItemRepositioned{
            agenda_item: agenda_item
          }
        },
        socket
      ) do
    items = upsert_agenda_item(socket.assigns.agenda_items, agenda_item)

    {:ok,
     socket
     |> assign(:agenda_items, items)
     |> assign(:chronological_warning, check_chronological_order(items))
     |> stream_insert(:agenda_items, to_change_form(agenda_item, %{}),
       at: agenda_item.position
     )}
  end

  def update(%{agenda: agenda} = _assigns, socket) do
    agenda_forms = Enum.map(agenda.agenda_items, &to_change_form(&1, %{}))

    {:ok,
     socket
     |> assign(agenda_id: agenda.id)
     |> assign(agenda_items: agenda.agenda_items)
     |> assign(
       chronological_warning: check_chronological_order(agenda.agenda_items)
     )
     |> stream(:agenda_items, agenda_forms)}
  end

  def handle_event("validate", %{"id" => id, "agenda_item" => params}, socket) do
    case find_agenda_item(socket, id) do
      nil ->
        {:noreply, socket}

      agenda_item ->
        {:noreply,
         stream_insert(
           socket,
           :agenda_items,
           to_change_form(agenda_item, params, :validate)
         )}
    end
  end

  def handle_event("validate", %{"agenda_item" => params}, socket) do
    agenda_item = build_agenda_item(socket.assigns.agenda_id)

    {:noreply,
     stream_insert(
       socket,
       :agenda_items,
       to_change_form(agenda_item, params, :validate)
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

    case find_agenda_item(socket, id) do
      nil ->
        {:noreply, socket}

      agenda_item ->
        if agenda_item.title == val do
          {:noreply, socket}
        else
          {:noreply,
           stream_insert(socket, :agenda_items, to_change_form(agenda_item, %{}))}
        end
    end
  end

  defp find_agenda_item(socket, id) do
    Enum.find(socket.assigns.agenda_items, &(to_string(&1.id) == to_string(id)))
  end

  defp upsert_agenda_item(items, agenda_item) do
    if Enum.any?(items, &(&1.id == agenda_item.id)) do
      Enum.map(items, fn item ->
        if item.id == agenda_item.id, do: agenda_item, else: item
      end)
    else
      items ++ [agenda_item]
    end
  end

  defp remove_agenda_item(items, agenda_item) do
    Enum.reject(items, &(&1.id == agenda_item.id))
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

  defp time_warning(start_time, end_time) do
    case {parse_time(start_time), parse_time(end_time)} do
      {{:ok, s}, {:ok, e}} ->
        if Time.compare(s, e) == :gt do
          "End time is before start time"
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp parse_time(nil), do: :error
  defp parse_time(""), do: :error
  defp parse_time(%Time{} = t), do: {:ok, t}

  defp parse_time(s) when is_binary(s) do
    case Time.from_iso8601(s) do
      {:ok, t} ->
        {:ok, t}

      {:error, _} ->
        case Time.from_iso8601(s <> ":00") do
          {:ok, t} -> {:ok, t}
          _ -> :error
        end
    end
  end

  defp check_chronological_order(items) do
    items
    |> Enum.sort_by(& &1.position)
    |> Enum.reject(&(&1.start_time == nil))
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [a, b] ->
      if a.start_time && b.start_time do
        Time.compare(a.start_time, b.start_time) == :gt or
          (a.end_time && Time.compare(a.end_time, b.start_time) == :gt)
      else
        false
      end
    end)
  end
end
