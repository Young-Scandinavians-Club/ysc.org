defmodule YscWeb.AgendasLive.FormComponent do
  use YscWeb, :live_component

  alias Ysc.Agendas

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.form
        :let={_f}
        for={@form}
        as={nil}
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        id={"agenda-title-form-#{@agenda_id}"}
      >
        <.input
          id={"#{@id}-title"}
          field={@form[:title]}
          type="text"
          label="Agenda Title"
          phx-blur={
            JS.dispatch("submit", to: "##{"agenda-title-form-#{@agenda_id}"}")
          }
        />
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{agenda: agenda} = assigns, socket) do
    changeset = Agendas.change_agenda(agenda)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"agenda" => agenda_params}, socket) do
    changeset =
      socket.assigns.agenda
      |> Agendas.change_agenda(agenda_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"agenda" => agenda_params}, socket) do
    # save_list(socket, socket.assigns.action, agenda_params)
    agenda = Agendas.get_agenda!(socket.assigns.agenda_id)
    Agendas.update_agenda(socket.assigns.event_id, agenda, agenda_params)
    {:noreply, socket}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
