defmodule YscWeb.EventPhotoUploadLive do
  @moduledoc """
  Minimal upload page for event attendees to contribute photos and videos after an event.
  """
  use YscWeb, :live_view

  import YscWeb.CoreComponents

  alias Ysc.EventPhotos
  alias Ysc.Events.DateTimeFormatter
  alias Ysc.Events.Event
  alias Ysc.GooglePhotos
  alias Ysc.GooglePhotos.Limits
  alias Ysc.SafeFile
  alias YscWeb.Workers.EventPhotoUploadWorker

  @impl true
  def mount(%{"upload_token" => upload_token}, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Share event photos & videos")
      |> assign(:upload_complete?, false)
      |> assign(:upload_errors, [])
      |> allow_upload(:photos,
        # Wildcards avoid per-extension MIME registration; Limits.validate_upload/2
        # enforces the supported photo/video extensions on the server.
        accept: ~w(image/* video/*),
        max_entries: 30,
        max_file_size: Limits.max_upload_bytes(),
        auto_upload: true
      )

    case EventPhotos.get_by_upload_token(upload_token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "This upload link is not valid.")
         |> push_navigate(to: ~p"/")}

      %{event: event} = collection ->
        cond do
          event.state not in [:published, "published"] ->
            {:ok,
             socket
             |> put_flash(
               :error,
               "Photo and video uploads are not available for this event."
             )
             |> push_navigate(to: ~p"/")}

          not EventPhotos.authorized_to_upload?(
            event,
            socket.assigns.current_user
          ) ->
            {:ok,
             socket
             |> put_flash(
               :error,
               "To upload photos, sign in with the same email address you used when you bought your ticket for this event. If you used a different email, sign out and sign in with the ticket email, or contact info@ysc.org for help."
             )
             |> push_navigate(to: ~p"/")}

          true ->
            user = socket.assigns.current_user

            {:ok,
             socket
             |> assign(:collection, collection)
             |> assign(:event, event)
             |> assign(:greeting_name, greeting_name(user))
             |> assign(
               :event_datetime_label,
               format_event_datetime_label(event)
             )
             |> assign(:dev_stub?, GooglePhotos.dev_stub_enabled?())
             |> assign(:uploads_available?, GooglePhotos.uploads_available?()),
             layout: {YscWeb.Layouts, :focus}}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="event-photo-upload-page" class="space-y-8">
      <div
        :if={@dev_stub?}
        class="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
      >
        Development mode: photos are saved locally and are not sent to Google Photos.
      </div>

      <.event_thanks_header
        event={@event}
        greeting_name={@greeting_name}
        event_datetime_label={@event_datetime_label}
        variant={if @upload_complete?, do: :success, else: :upload}
      />

      <%= if @upload_complete? do %>
        <div class="text-center space-y-4">
          <div class="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-green-100">
            <.icon name="hero-check" class="h-8 w-8 text-green-600" />
          </div>
          <p class="text-zinc-600 leading-relaxed">
            Your photos and videos are on their way into the shared album for <span class="font-medium text-zinc-800">{@event.title}</span>.
            Thanks again for helping us remember a wonderful evening together.
          </p>
          <p class="text-sm text-zinc-500">
            You can close this page, or add more if you have them.
          </p>
          <.button phx-click="upload-more" variant="outline" id="upload-more-btn">
            Upload more
          </.button>
        </div>
      <% else %>
        <p class="text-center text-zinc-600 leading-relaxed -mt-2">
          Drag photos and videos below or tap to browse. You can add up to 30 files per batch; after you submit, use Upload more to add another batch.
        </p>

        <%= if not @uploads_available? do %>
          <div class="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
            Uploads are temporarily unavailable. Please try again later.
          </div>
        <% else %>
          <form
            id="event-photo-upload-form"
            phx-submit="upload"
            phx-change="validate"
            class="space-y-6"
          >
            <label
              id="photo-drop-zone"
              phx-drop-target={@uploads.photos.ref}
              class={[
                "flex flex-col items-center justify-center rounded-xl border-2 border-dashed px-6 py-16 cursor-pointer transition",
                "border-zinc-300 bg-white hover:border-blue-400 hover:bg-blue-50/30"
              ]}
            >
              <.icon name="hero-arrow-up-tray" class="h-12 w-12 text-zinc-400 mb-4" />
              <span class="text-base font-medium text-zinc-800">
                Drop photos and videos here or click to browse
              </span>
              <span class="mt-2 text-sm text-zinc-500">
                Photos up to 200 MB · Videos up to 20 GB
              </span>
              <span class="mt-1 text-xs text-zinc-400">
                JPG, PNG, HEIC, WebP, MP4, MOV, and more
              </span>
              <.live_file_input upload={@uploads.photos} class="hidden" />
            </label>

            <ul :if={@upload_errors != []} class="text-sm text-red-600 space-y-1">
              <li :for={msg <- @upload_errors}>{msg}</li>
            </ul>

            <div :if={@uploads.photos.entries != []} class="space-y-3">
              <p class="text-sm font-medium text-zinc-700">
                {length(@uploads.photos.entries)} file(s) selected
              </p>
              <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
                <div
                  :for={entry <- @uploads.photos.entries}
                  class={[
                    "relative rounded-lg overflow-hidden border-2 aspect-square",
                    if(entry_has_errors?(@uploads.photos, entry),
                      do: "border-red-400 bg-red-50",
                      else: "border-zinc-200 bg-zinc-100"
                    )
                  ]}
                >
                  <%= if video_entry?(entry) do %>
                    <div class="flex h-full w-full flex-col items-center justify-center gap-2 p-3">
                      <.icon name="hero-film" class="h-10 w-10 text-zinc-500" />
                      <span class="text-xs font-medium text-zinc-600">Video</span>
                    </div>
                  <% else %>
                    <.live_img_preview
                      entry={entry}
                      class="h-full w-full object-cover"
                    />
                  <% end %>
                  <button
                    type="button"
                    phx-click="cancel-upload"
                    phx-value-ref={entry.ref}
                    class="absolute top-1 right-1 rounded-full bg-zinc-900/70 p-1 text-white hover:bg-zinc-900"
                    aria-label="Remove"
                  >
                    <.icon name="hero-x-mark" class="h-4 w-4" />
                  </button>
                  <div class="absolute bottom-0 inset-x-0 space-y-1 bg-zinc-900/70 px-2 py-1">
                    <p class="text-xs text-white truncate">{entry.client_name}</p>
                    <%= cond do %>
                      <% entry_has_errors?(@uploads.photos, entry) -> %>
                        <p class="text-[11px] font-medium text-red-300">
                          <%= for err <- upload_errors(@uploads.photos, entry) do %>
                            {YscWeb.UploadErrors.error_to_string(err, :event_photo)}
                          <% end %>
                        </p>
                      <% entry.done? -> %>
                        <p class="flex items-center gap-1 text-[11px] font-medium text-green-300">
                          <.icon name="hero-check-circle" class="h-3 w-3 shrink-0" />
                          Ready
                        </p>
                      <% true -> %>
                        <div class="h-1.5 w-full overflow-hidden rounded-full bg-white/20">
                          <div
                            class="h-full rounded-full bg-blue-400 transition-all duration-150"
                            style={"width: #{entry.progress}%"}
                          />
                        </div>
                        <p class="text-[11px] text-zinc-200">
                          Uploading… {entry.progress}%
                        </p>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>

            <div class="flex flex-col gap-2">
              <p
                :if={
                  @uploads.photos.entries != [] and
                    not uploads_ready?(@uploads.photos)
                }
                class="text-center text-sm text-zinc-500"
                aria-live="polite"
              >
                Uploading {entries_ready_count(@uploads.photos)} of {length(
                  @uploads.photos.entries
                )} files… please keep this page open.
              </p>
              <.button
                type="submit"
                id="submit-photos-btn"
                class="w-full"
                disabled={
                  @uploads.photos.entries == [] or
                    not uploads_ready?(@uploads.photos)
                }
                phx-disable-with="Uploading…"
              >
                <%= if @uploads.photos.entries != [] and not uploads_ready?(@uploads.photos) do %>
                  Waiting for files to finish uploading…
                <% else %>
                  Upload
                <% end %>
              </.button>
              <p
                :for={err <- collect_upload_errors(@uploads.photos)}
                class="text-sm text-red-600"
              >
                {YscWeb.UploadErrors.error_to_string(err, :event_photo)}
              </p>
            </div>
          </form>
        <% end %>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, assign(socket, :upload_errors, [])}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :photos, ref)}
  end

  def handle_event("upload-more", _params, socket) do
    {:noreply,
     socket
     |> assign(:upload_complete?, false)
     |> assign(:upload_errors, [])}
  end

  def handle_event("upload", _params, socket) do
    if socket.assigns.uploads_available? do
      entries = socket.assigns.uploads.photos.entries

      validation_errors =
        Enum.flat_map(entries, fn entry ->
          case Limits.validate_upload(entry.client_name, entry.client_size) do
            :ok ->
              []

            {:error, reason} ->
              ["#{entry.client_name}: #{Limits.error_message(reason)}"]
          end
        end)

      if validation_errors != [] do
        {:noreply, assign(socket, :upload_errors, validation_errors)}
      else
        do_upload(socket)
      end
    else
      {:noreply,
       put_flash(socket, :error, "Uploads are temporarily unavailable.")}
    end
  end

  defp do_upload(socket) do
    collection = socket.assigns.collection
    user = socket.assigns.current_user
    entry_count = length(socket.assigns.uploads.photos.entries)

    uploaded =
      consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
        tmp_root = SafeFile.event_photo_tmp_root()

        with {:ok, dest} <-
               SafeFile.event_photo_tmp_path(
                 collection.id,
                 entry.uuid,
                 entry.client_name
               ),
             {:ok, dest} <- SafeFile.copy_upload_to(path, tmp_root, dest),
             {:ok, _job} <- enqueue_upload_job(collection, user, dest, entry) do
          {:ok, dest}
        else
          {:error, _} ->
            cleanup_staged_upload(tmp_root, collection, entry)
            {:error, :upload_enqueue_failed}
        end
      end)

    uploaded_count = length(uploaded)

    cond do
      uploaded_count == 0 ->
        {:noreply,
         put_flash(socket, :error, "Please wait for files to finish uploading.")}

      uploaded_count < entry_count ->
        {:noreply,
         socket
         |> assign(:upload_complete?, true)
         |> assign(:upload_errors, [
           "Some files could not be queued for upload. Please try again."
         ])
         |> put_flash(:error, "Some files could not be queued for upload.")}

      true ->
        {:noreply,
         socket
         |> assign(:upload_complete?, true)
         |> assign(:upload_errors, [])
         |> YscWeb.Flash.put_toast(
           :info,
           "Your files are being uploaded. Thank you for contributing!",
           title: "Upload"
         )}
    end
  end

  defp enqueue_upload_job(collection, user, dest, entry) do
    %{
      "collection_id" => collection.id,
      "file_path" => dest,
      "filename" => entry.client_name,
      "user_id" => user.id
    }
    |> EventPhotoUploadWorker.new()
    |> Oban.insert()
  end

  defp cleanup_staged_upload(tmp_root, collection, entry) do
    case SafeFile.event_photo_tmp_path(
           collection.id,
           entry.uuid,
           entry.client_name
         ) do
      {:ok, dest} -> SafeFile.rm_under_root(tmp_root, dest)
      :error -> :ok
    end
  end

  defp uploads_ready?(upload) do
    Enum.all?(upload.entries, fn e -> e.done? end)
  end

  defp entries_ready_count(upload) do
    Enum.count(upload.entries, & &1.done?)
  end

  defp entry_has_errors?(upload, entry) do
    upload_errors(upload, entry) != []
  end

  defp collect_upload_errors(%{entries: entries} = upload) do
    Enum.flat_map(entries, fn entry ->
      upload_errors(upload, entry)
    end)
  end

  defp video_entry?(entry) do
    client_type = entry.client_type || ""

    String.starts_with?(client_type, "video") or
      Limits.video?(entry.client_name)
  end

  attr :event, Event, required: true
  attr :greeting_name, :string, required: true
  attr :event_datetime_label, :string, default: nil
  attr :variant, :atom, default: :upload

  defp event_thanks_header(assigns) do
    ~H"""
    <div
      id="event-photo-thanks-intro"
      class="rounded-2xl border border-zinc-200 bg-white px-6 py-8 text-center shadow-sm"
    >
      <p class="text-sm font-medium uppercase tracking-wide text-blue-700">
        Thank you for being there
      </p>

      <h1 class="mt-3 text-2xl font-semibold text-zinc-900 leading-tight">
        <%= if @variant == :success do %>
          Tusen tack!
        <% else %>
          <%= if @greeting_name != "" do %>
            Hej {@greeting_name},
          <% else %>
            Hej,
          <% end %>
        <% end %>
      </h1>

      <p class="mt-4 text-zinc-600 leading-relaxed">
        <%= if @variant == :success do %>
          It meant a lot to have you at this event. Your photos and videos help keep the spirit of the evening alive for everyone in our community.
        <% else %>
          We're so glad you joined us. If you captured a moment from the event — a photo or a clip — we'd love to include it in our shared album so the whole club can relive the day together.
        <% end %>
      </p>

      <div class="mt-6 pt-6 border-t border-zinc-100 space-y-2">
        <p class="text-lg font-semibold text-zinc-800">{@event.title}</p>

        <div class="flex flex-col gap-1.5 text-sm text-zinc-500">
          <p
            :if={@event_datetime_label}
            class="inline-flex items-center justify-center gap-1.5"
          >
            <.icon name="hero-calendar-days" class="h-4 w-4 shrink-0" />
            {@event_datetime_label}
          </p>
          <p
            :if={@event.location_name && @event.location_name != ""}
            class="inline-flex items-center justify-center gap-1.5"
          >
            <.icon name="hero-map-pin" class="h-4 w-4 shrink-0" />
            {@event.location_name}
          </p>
        </div>
      </div>

      <p :if={@variant == :upload} class="mt-6 text-base font-medium text-zinc-800">
        Share your photos & videos
      </p>
    </div>
    """
  end

  defp greeting_name(%{first_name: name}) when is_binary(name) and name != "" do
    String.trim(name)
  end

  defp greeting_name(_), do: ""

  defp format_event_datetime_label(%Event{} = event) do
    label =
      DateTimeFormatter.format_datetime(%{
        start_date: event.start_date,
        start_time: event.start_time,
        end_date: event.end_date,
        end_time: event.end_time
      })

    if is_binary(label) and label != "", do: label, else: nil
  end
end
