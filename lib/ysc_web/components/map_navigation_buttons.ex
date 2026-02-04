defmodule YscWeb.Components.MapNavigationButtons do
  @moduledoc """
  Component for displaying Google Maps navigation buttons.

  Provides buttons for walking, driving, transit, and bicycling directions.
  """
  use Phoenix.Component

  attr :latitude, :float, required: true, doc: "Latitude of the destination"
  attr :longitude, :float, required: true, doc: "Longitude of the destination"
  attr :class, :string, default: "", doc: "Additional CSS classes"

  def map_navigation_buttons(assigns) do
    ~H"""
    <div class={@class}>
      <ul class="flex flex-row items-center justify-center py-4 space-x-8 list-none w-full">
        <li class="p-0 m-0">
          <.navigation_link
            href={"https://maps.google.com/?saddr=Current+Location&daddr=#{@latitude},#{@longitude}&dirflg=w"}
            label="Walking directions"
          >
            <svg
              stroke-width="0"
              viewBox="0 0 320 512"
              xmlns="http://www.w3.org/2000/svg"
              class="w-6 h-6 text-zinc-600 fill-zinc-600 group-hover:fill-blue-600 group-hover:text-blue-600 transition ease-in-out duration-200"
            >
              <path d="M208 96c26.5 0 48-21.5 48-48S234.5 0 208 0s-48 21.5-48 48 21.5 48 48 48zm94.5 149.1l-23.3-11.8-9.7-29.4c-14.7-44.6-55.7-75.8-102.2-75.9-36-.1-55.9 10.1-93.3 25.2-21.6 8.7-39.3 25.2-49.7 46.2L17.6 213c-7.8 15.8-1.5 35 14.2 42.9 15.6 7.9 34.6 1.5 42.5-14.3L81 228c3.5-7 9.3-12.5 16.5-15.4l26.8-10.8-15.2 60.7c-5.2 20.8.4 42.9 14.9 58.8l59.9 65.4c7.2 7.9 12.3 17.4 14.9 27.7l18.3 73.3c4.3 17.1 21.7 27.6 38.8 23.3 17.1-4.3 27.6-21.7 23.3-38.8l-22.2-89c-2.6-10.3-7.7-19.9-14.9-27.7l-45.5-49.7 17.2-68.7 5.5 16.5c5.3 16.1 16.7 29.4 31.7 37l23.3 11.8c15.6 7.9 34.6 1.5 42.5-14.3 7.7-15.7 1.4-35.1-14.3-43zM73.6 385.8c-3.2 8.1-8 15.4-14.2 21.5l-50 50.1c-12.5 12.5-12.5 32.8 0 45.3s32.7 12.5 45.2 0l59.4-59.4c6.1-6.1 10.9-13.4 14.2-21.5l13.5-33.8c-55.3-60.3-38.7-41.8-47.4-53.7l-20.7 51.5z">
              </path>
            </svg>
          </.navigation_link>
        </li>

        <li class="p-0 m-0">
          <.navigation_link
            href={"https://www.google.com/maps?saddr=Current+Location&daddr=#{@latitude},#{@longitude}&mode=driving"}
            label="Driving directions"
          >
            <svg
              stroke-width="0"
              viewBox="0 0 512 512"
              xmlns="http://www.w3.org/2000/svg"
              class="w-6 h-6 text-zinc-600 fill-zinc-600 group-hover:fill-blue-600 group-hover:text-blue-600 transition ease-in-out duration-200"
            >
              <path d="M499.99 176h-59.87l-16.64-41.6C406.38 91.63 365.57 64 319.5 64h-127c-46.06 0-86.88 27.63-103.99 70.4L71.87 176H12.01C4.2 176-1.53 183.34.37 190.91l6 24C7.7 220.25 12.5 224 18.01 224h20.07C24.65 235.73 16 252.78 16 272v48c0 16.12 6.16 30.67 16 41.93V416c0 17.67 14.33 32 32 32h32c17.67 0 32-14.33 32-32v-32h256v32c0 17.67 14.33 32 32 32h32c17.67 0 32-14.33 32-32v-54.07c9.84-11.25 16-25.8 16-41.93v-48c0-19.22-8.65-36.27-22.07-48H494c5.51 0 10.31-3.75 11.64-9.09l6-24c1.89-7.57-3.84-14.91-11.65-14.91zm-352.06-17.83c7.29-18.22 24.94-30.17 44.57-30.17h127c19.63 0 37.28 11.95 44.57 30.17L384 208H128l19.93-49.83zM96 319.8c-19.2 0-32-12.76-32-31.9S76.8 256 96 256s48 28.71 48 47.85-28.8 15.95-48 15.95zm320 0c-19.2 0-48 3.19-48-15.95S396.8 256 416 256s32 12.76 32 31.9-12.8 31.9-32 31.9z">
              </path>
            </svg>
          </.navigation_link>
        </li>

        <li class="p-0 m-0">
          <.navigation_link
            href={"https://maps.google.com/?saddr=Current+Location&daddr=#{@latitude},#{@longitude}&mode=transit&dirflg=r"}
            label="Transit directions"
          >
            <svg
              stroke-width="0"
              viewBox="0 0 576 512"
              xmlns="http://www.w3.org/2000/svg"
              class="w-6 h-6 text-zinc-600 fill-zinc-600 group-hover:fill-blue-600 group-hover:text-blue-600 transition ease-in-out duration-200"
            >
              <path d="M288 0C422.4 0 512 35.2 512 80l0 16 0 32c17.7 0 32 14.3 32 32l0 64c0 17.7-14.3 32-32 32l0 160c0 17.7-14.3 32-32 32l0 32c0 17.7-14.3 32-32 32l-32 0c-17.7 0-32-14.3-32-32l0-32-192 0 0 32c0 17.7-14.3 32-32 32l-32 0c-17.7 0-32-14.3-32-32l0-32c-17.7 0-32-14.3-32-32l0-160c-17.7 0-32-14.3-32-32l0-64c0-17.7 14.3-32 32-32c0 0 0 0 0 0l0-32s0 0 0 0l0-16C64 35.2 153.6 0 288 0zM128 160l0 96c0 17.7 14.3 32 32 32l112 0 0-160-112 0c-17.7 0-32 14.3-32 32zM304 288l112 0c17.7 0 32-14.3 32-32l0-96c0-17.7-14.3-32-32-32l-112 0 0 160zM144 400a32 32 0 1 0 0-64 32 32 0 1 0 0 64zm288 0a32 32 0 1 0 0-64 32 32 0 1 0 0 64zM384 80c0-8.8-7.2-16-16-16L208 64c-8.8 0-16 7.2-16 16s7.2 16 16 16l160 0c8.8 0 16-7.2 16-16z">
              </path>
            </svg>
          </.navigation_link>
        </li>

        <li class="p-0 m-0">
          <.navigation_link
            href={"https://www.google.com/maps?saddr=Current+Location&daddr=#{@latitude},#{@longitude}&mode=bicycling&dirflg=b"}
            label="Bicycling directions"
          >
            <svg
              stroke-width="0"
              viewBox="0 0 640 512"
              xmlns="http://www.w3.org/2000/svg"
              class="w-6 h-6 text-zinc-600 fill-zinc-600 group-hover:fill-blue-600 group-hover:text-blue-600 transition ease-in-out duration-200"
            >
              <path d="M512.509 192.001c-16.373-.064-32.03 2.955-46.436 8.495l-77.68-125.153A24 24 0 0 0 368.001 64h-64c-8.837 0-16 7.163-16 16v16c0 8.837 7.163 16 16 16h50.649l14.896 24H256.002v-16c0-8.837-7.163-16-16-16h-87.459c-13.441 0-24.777 10.999-24.536 24.437.232 13.044 10.876 23.563 23.995 23.563h48.726l-29.417 47.52c-13.433-4.83-27.904-7.483-42.992-7.52C58.094 191.83.412 249.012.002 319.236-.413 390.279 57.055 448 128.002 448c59.642 0 109.758-40.793 123.967-96h52.033a24 24 0 0 0 20.406-11.367L410.37 201.77l14.938 24.067c-25.455 23.448-41.385 57.081-41.307 94.437.145 68.833 57.899 127.051 126.729 127.719 70.606.685 128.181-55.803 129.255-125.996 1.086-70.941-56.526-129.72-127.476-129.996zM186.75 265.772c9.727 10.529 16.673 23.661 19.642 38.228h-43.306l23.664-38.228zM128.002 400c-44.112 0-80-35.888-80-80s35.888-80 80-80c5.869 0 11.586.653 17.099 1.859l-45.505 73.509C89.715 331.327 101.213 352 120.002 352h81.3c-12.37 28.225-40.562 48-73.3 48zm162.63-96h-35.624c-3.96-31.756-19.556-59.894-42.383-80.026L237.371 184h127.547l-74.286 120zm217.057 95.886c-41.036-2.165-74.049-35.692-75.627-76.755-.812-21.121 6.633-40.518 19.335-55.263l44.433 71.586c4.66 7.508 14.524 9.816 22.032 5.156l13.594-8.437c7.508-4.66 9.817-14.524 5.156-22.032l-44.468-71.643a79.901 79.901 0 0 1 19.858-2.497c44.112 0 80 35.888 80 80-.001 45.54-38.252 82.316-84.313 79.885z">
              </path>
            </svg>
          </.navigation_link>
        </li>
      </ul>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  defp navigation_link(assigns) do
    ~H"""
    <a
      href={@href}
      target="_blank"
      class="group hover:blue-600 hover:fill-blue-600 transition ease-in-out duration-200"
      aria-label={@label}
    >
      <%= render_slot(@inner_block) %>
    </a>
    """
  end
end
