defmodule YscWeb.UploadComponent do
  @moduledoc """
  LiveView component for file uploads.

  Provides an interface for uploading files with drag-and-drop support.
  """
  use YscWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> allow_upload(:upload_component_file,
       accept: ~w(.jpg .jpeg .png .gif .webp),
       max_entries: 1,
       auto_upload: true
     )}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form
      id={"#{@id}-upload-form"}
      class="upload-component space-y-4"
      action="#"
      phx-change="validate"
      phx-drop-target={@uploads.upload_component_file.ref}
      phx-submit="save"
      phx-target={@myself}
      data-user_id={@user_id}
    >
      <label
        phx-drop-target={@uploads.upload_component_file.ref}
        class={upload_dropzone_label_class()}
      >
        <.live_file_input upload={@uploads.upload_component_file} class="hidden" />

        <div class="flex flex-row flex-wrap gap-2">
          <%= for entry <- @uploads.upload_component_file.entries do %>
            <article class="upload-entry">
              <.upload_entry_preview
                entry={entry}
                cancel="cancel"
                preview_class="group-hover:blur-sm h-80 w-full"
                button_class="upload-entry__cancel w-full"
                phx-target={@myself}
              />

              <%= for err <- upload_errors(@uploads.upload_component_file, entry) do %>
                <.upload_error error={err} alert? />
              <% end %>
            </article>
          <% end %>
        </div>

        <%= for err <- upload_errors(@uploads.upload_component_file) do %>
          <.upload_error error={err} alert? />
        <% end %>

        <div :if={length(@uploads.upload_component_file.entries) == 0}>
          <.upload_dropzone_empty_state />
        </div>
      </label>

      <.button type="submit" phx-disable-with="Uploading...">Upload</.button>
    </form>
    """
  end

  @impl true
  def handle_event("validate", _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :upload_component_file, ref)}
  end

  def handle_event("save", _params, socket) do
    case YscWeb.Uploads.consume_entries(socket, :upload_component_file) do
      [] -> :ok
      [upload_path] -> hoist_upload(socket, upload_path)
    end

    {:noreply, socket}
  end

  defp hoist_upload(socket, upload_path) do
    send(self(), {__MODULE__, socket.assigns.id, upload_path})
    :ok
  end
end
