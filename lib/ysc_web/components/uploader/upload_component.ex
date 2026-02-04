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
        class="flex p-6 flex-col items-center justify-center w-full min-h-72 border-2 border-zinc-300 border-dashed rounded-lg cursor-pointer bg-zinc-50 hover:bg-zinc-100"
      >
        <.live_file_input upload={@uploads.upload_component_file} class="hidden" />

        <div class="flex flex-row flex-wrap gap-2">
          <%= for entry <- @uploads.upload_component_file.entries do %>
            <article class="upload-entry">
              <figure class="group relative">
                <button
                  type="button"
                  aria-label="cancel"
                  phx-click="cancel"
                  phx-target={@myself}
                  phx-value-ref={entry.ref}
                  class="upload-entry__cancel w-full"
                >
                  <div class="hidden group-hover:block absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 text-red-500 z-10">
                    <.icon name="hero-x-circle" class="w-10 h-10" />
                  </div>
                  <.live_img_preview
                    entry={entry}
                    class="group-hover:blur h-80 w-full"
                  />
                  <figcaption class="text-sm truncate overflow-hidden bg-zinc-100 text-zinc-600 w-28 z-8 absolute inset-x-0 bottom-0 py-1">
                    <%= entry.client_name %>
                  </figcaption>
                </button>
              </figure>

              <%!-- Phoenix.Component.upload_errors/2 returns a list of error atoms --%>
              <%= for err <- upload_errors(@uploads.upload_component_file, entry) do %>
                <p class="alert alert-danger text-sm text-red-600 font-semibold mt-1">
                  <.icon name="hero-exclamation-circle" class="-mt-0.5 h-5 w-5" /> <%= error_to_string(
                    err
                  ) %>
                </p>
              <% end %>
            </article>
          <% end %>
        </div>

        <%= for err <- upload_errors(@uploads.upload_component_file) do %>
          <p class="alert alert-danger text-sm text-red-600 font-semibold mt-1">
            <.icon name="hero-exclamation-circle" class="-mt-0.5 h-5 w-5" /> <%= error_to_string(
              err
            ) %>
          </p>
        <% end %>

        <div
          :if={length(@uploads.upload_component_file.entries) == 0}
          class="flex flex-col items-center justify-center pt-5 pb-6"
        >
          <.icon name="hero-cloud-arrow-up" class="w-8 h-10 mb-4 text-zinc-500" />
          <p class="mb-2 text-sm text-zinc-500">
            <span class="font-semibold">Click to upload</span> or drag and drop
          </p>
          <p class="text-xs text-zinc-500">
            SVG, PNG, JPG, JPEG or GIF
          </p>
        </div>
      </label>

      <.button type="submit">Upload</.button>
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

  defp error_to_string(:too_large), do: "Too large"

  defp error_to_string(:not_accepted),
    do: "You have selected an unacceptable file type"

  defp error_to_string(:too_many_files), do: "You have selected too many files"
end
