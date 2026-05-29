defmodule YscWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At the first glance, this module may seem daunting, but its goal is
  to provide some core building blocks in your application, such as modals,
  tables, and forms. The components are mostly markup and well documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component
  use Gettext, backend: YscWeb.Gettext
  use YscWeb, :verified_routes

  import Phoenix.Controller, only: [get_csrf_token: 0]

  alias Phoenix.LiveView.JS
  alias YscWeb.FormHelpers

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        This is a modal.
      </.modal>

  JS commands may be passed to the `:on_cancel` to configure
  the closing/cancel event, for example:

      <.modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
        This is another modal.
      </.modal>

  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :fullscreen, :boolean, default: false
  attr :max_width, :string, default: "max-w-3xl"
  attr :on_cancel, JS, default: %JS{}
  attr :z_index, :string, default: "z-[200]"
  slot :inner_block, required: true

  def modal(assigns) do
    assigns = assign_new(assigns, :z_index, fn -> "z-[200]" end)

    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class={"relative #{@z_index} hidden"}
    >
      <%!-- No aria-hidden on backdrop: dialog has aria-modal="true"; avoids blocking focus/hidden violation --%>
      <div id={"#{@id}-bg"} class="fixed inset-0 transition-opacity bg-zinc-50/90" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex items-center justify-center min-h-full">
          <div class={[
            "w-full sm:p-4 sm:py-6 lg:py-8",
            unless(@fullscreen == true, do: @max_width, else: "")
          ]}>
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="relative hidden transition bg-white shadow-lg shadow-zinc-700/10 ring-zinc-700/10 ring-1 p-6 sm:p-8 min-h-screen sm:min-h-fit sm:rounded"
            >
              <div class="absolute top-1 right-2 sm:top-0.5 sm:right-1 z-20">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="group flex-none rounded-full bg-white/90 backdrop-blur-sm shadow-md hover:shadow-lg hover:bg-white active:scale-95 focus:outline-none focus-visible:ring-2 focus-visible:ring-zinc-400 focus-visible:ring-offset-2 p-2 transition-all duration-200 ease-out hover:scale-110"
                  aria-label={gettext("close")}
                >
                  <.icon
                    name="hero-x-mark-solid"
                    class="w-5 h-5 text-zinc-700 group-hover:text-zinc-900 group-hover:rotate-90 transition-all duration-200 ease-out"
                  />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
      <.flash kind={:error} id="sys-msg" dismissable={false}>System status…</.flash>
  """
  attr :id, :string, default: "flash", doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil

  attr :kind, :atom,
    values: [:info, :error],
    doc: "used for styling and flash lookup"

  attr :rest, :global,
    doc: "the arbitrary HTML attributes to add to the flash container"

  attr :class, :string, default: nil

  attr :dismissable, :boolean,
    default: true,
    doc:
      "when false, omits the close control and click-to-dismiss (for system-driven flashes)"

  slot :inner_block,
    doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={
        if @dismissable,
          do: JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")
      }
      role="alert"
      class={[
        "fixed top-2 right-2 w-80 sm:w-96 z-[110] rounded-xl p-3 ring-1",
        @class,
        @kind == :info &&
          "bg-emerald-50 text-emerald-800 ring-emerald-500 fill-cyan-900",
        @kind == :error &&
          "bg-rose-50 text-rose-900 shadow-md ring-rose-500 fill-rose-900"
      ]}
      {@rest}
    >
      <p
        :if={@title}
        class="flex items-center gap-1.5 text-sm font-semibold leading-6"
      >
        <.icon
          :if={@kind == :info}
          name="hero-information-circle-mini"
          class="w-4 h-4"
        />
        <.icon
          :if={@kind == :error}
          name="hero-exclamation-circle-mini"
          class="w-4 h-4"
        />
        {@title}
      </p>
      <p class="mt-2 text-sm leading-5">{msg}</p>
      <button
        :if={@dismissable}
        type="button"
        class="absolute p-2 group top-1 right-1"
        aria-label={gettext("close")}
      >
        <.icon
          name="hero-x-mark-solid"
          class="w-5 h-5 opacity-40 group-hover:opacity-70"
        />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  def flash_group(assigns) do
    # client-error: shown only after LiveSocket.disconnectedTimeout (see app.js) so short
    # blips do not flash the message. Hidden immediately on reconnect via phx-connected.
    ~H"""
    <.flash id="flash-info" kind={:info} title="Success!" flash={@flash} />
    <.flash id="flash-error" kind={:error} title="Error!" flash={@flash} />
    <.flash
      id="client-error"
      kind={:error}
      title="We can't find the internet"
      dismissable={false}
      phx-disconnected={show(".phx-client-error #client-error")}
      phx-connected={hide("#client-error")}
      hidden
    >
      Attempting to reconnect
      <.icon name="hero-arrow-path" class="w-3 h-3 ml-1 animate-spin" />
    </.flash>

    <.flash
      id="server-error"
      kind={:error}
      title="Something went wrong!"
      dismissable={false}
      phx-disconnected={show(".phx-server-error #server-error")}
      phx-connected={hide("#server-error")}
      hidden
    >
      Hang in there while we get back on track
      <.icon name="hero-arrow-path" class="w-3 h-3 ml-1 animate-spin" />
    </.flash>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the datastructure for the form"

  attr :as, :any,
    default: nil,
    doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include:
      ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="space-y-8 bg-white">
        {render_slot(@inner_block, f)}
        <div
          :for={action <- @actions}
          class="flex items-center justify-between gap-6 mt-2"
        >
          {render_slot(action, f)}
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a `<button>` or a LiveView `<.link>` styled as a button.

  When `navigate`, `patch`, or `href` is set, renders `<.link>`; otherwise renders `<button>`.

  For LiveView interactions, pass `phx-disable-with` (or `loading_text`) with a short label
  (for example, `"Saving..."`). When structured loading applies, that attribute is **not**
  forwarded to the DOM; instead the component renders a spinner plus that label whenever
  LiveView applies `phx-*-loading` classes, avoiding `phx-disable-with`'s `textContent` swap
  (which would break the loading markup). When structured loading does not apply, the
  attribute is left unchanged for LiveView's default behavior.

  If you omit both `loading_text` and `phx-disable-with` on a **LiveView** control (`navigate`,
  `patch`, `href`, `type="submit"`, or `phx-click` / `phx-submit` / `phx-change` / `phx-hook`),
  the label defaults to `"Loading..."` so the spinner state is used after a press.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
      <.button type="submit" phx-disable-with="Saving...">Save</.button>
      <.button variant="outline" color="zinc">Outlined Button</.button>
      <.button patch={~p"/posts"} loading_text="Loading...">Back</.button>
  """
  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :color, :string, default: "blue"
  attr :variant, :string, default: "solid"
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :href, :string, default: nil
  attr :loading_text, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value method rel replace)

  slot :inner_block, required: true

  def button(assigns) do
    variant = assigns[:variant] || "solid"
    color = assigns[:color] || "blue"
    rest_raw = normalize_rest(assigns[:rest])
    disable_with = read_phx_disable_with(rest_raw)

    is_link =
      [assigns[:navigate], assigns[:patch], assigns[:href]]
      |> Enum.any?(&(&1 not in [nil, ""]))

    loading_text =
      case assigns[:loading_text] do
        nil -> loading_text_to_string(disable_with)
        "" -> loading_text_to_string(disable_with)
        other -> loading_text_to_string(other)
      end

    loading_text =
      if loading_text in [nil, ""] and
           (is_link or phx_live_button?(rest_raw) or assigns[:type] == "submit") do
        "Loading..."
      else
        loading_text
      end

    use_loading_ui? =
      use_button_loading_ui?(
        loading_text,
        is_link,
        rest_raw,
        assigns[:type]
      )

    rest =
      if use_loading_ui? do
        delete_phx_disable_with(rest_raw)
      else
        rest_raw
      end

    base_classes =
      [
        "group relative inline-flex items-center justify-center gap-2 whitespace-nowrap",
        "rounded py-2 px-3 min-h-[44px] transition duration-150 ease-in-out",
        "text-sm font-semibold leading-6",
        "disabled:cursor-not-allowed disabled:opacity-80",
        "phx-click-loading:pointer-events-none phx-submit-loading:pointer-events-none phx-change-loading:pointer-events-none",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-600 focus-visible:ring-offset-2"
      ]

    variant_classes =
      case variant do
        "outline" ->
          Map.get(button_outline_color_classes(), color) ||
            Map.get(button_outline_color_classes(), "blue")

        _ ->
          Map.get(button_solid_color_classes(), color) ||
            Map.get(button_solid_color_classes(), "blue")
      end

    assigns =
      assigns
      |> assign(:rest, rest)
      |> assign(:loading_text, loading_text)
      |> assign(:is_link, is_link)
      |> assign(:use_loading_ui?, use_loading_ui?)
      |> assign(:base_classes, base_classes)
      |> assign(:variant_classes, variant_classes)

    ~H"""
    <.link
      :if={@is_link}
      navigate={@navigate}
      patch={@patch}
      href={@href}
      class={[
        @base_classes,
        @variant_classes,
        @class
      ]}
      {@rest}
    >
      <%= if @use_loading_ui? do %>
        <span class="inline-flex items-center justify-center gap-2 group-[.phx-click-loading]:hidden group-[.phx-submit-loading]:hidden group-[.phx-change-loading]:hidden">
          {render_slot(@inner_block)}
        </span>
        <span
          class="hidden items-center justify-center gap-2 group-[.phx-click-loading]:inline-flex group-[.phx-submit-loading]:inline-flex group-[.phx-change-loading]:inline-flex"
          role="status"
        >
          <.icon
            name="hero-arrow-path"
            class="h-4 w-4 shrink-0 animate-spin text-current"
          />
          <span class="text-current">{@loading_text}</span>
        </span>
      <% else %>
        {render_slot(@inner_block)}
      <% end %>
    </.link>
    <button
      :if={!@is_link}
      type={@type}
      class={[@base_classes, @variant_classes, @class]}
      {@rest}
    >
      <%= if @use_loading_ui? do %>
        <span class="inline-flex items-center justify-center gap-2 group-[.phx-click-loading]:hidden group-[.phx-submit-loading]:hidden group-[.phx-change-loading]:hidden">
          {render_slot(@inner_block)}
        </span>
        <span
          class="hidden items-center justify-center gap-2 group-[.phx-click-loading]:inline-flex group-[.phx-submit-loading]:inline-flex group-[.phx-change-loading]:inline-flex"
          role="status"
        >
          <.icon
            name="hero-arrow-path"
            class="h-4 w-4 shrink-0 animate-spin text-current"
          />
          <span class="text-current">{@loading_text}</span>
        </span>
      <% else %>
        {render_slot(@inner_block)}
      <% end %>
    </button>
    """
  end

  defp normalize_rest(nil), do: %{}
  defp normalize_rest(rest) when is_map(rest), do: rest
  defp normalize_rest(rest) when is_list(rest), do: Map.new(rest)

  defp loading_text_to_string(nil), do: nil
  defp loading_text_to_string(text), do: to_string(text)

  defp read_phx_disable_with(rest) do
    rest = normalize_rest(rest)
    key_a = :"phx-disable-with"
    key_b = "phx-disable-with"

    cond do
      Map.has_key?(rest, key_a) -> Map.get(rest, key_a)
      Map.has_key?(rest, key_b) -> Map.get(rest, key_b)
      true -> nil
    end
  end

  defp delete_phx_disable_with(rest) do
    rest = normalize_rest(rest)
    key_a = :"phx-disable-with"
    key_b = "phx-disable-with"

    rest
    |> Map.delete(key_a)
    |> Map.delete(key_b)
  end

  defp use_button_loading_ui?(loading_text, is_link, rest, type) do
    loading_text not in [nil, ""] and
      (is_link or type != "button" or phx_live_button?(rest))
  end

  defp phx_live_button?(rest) do
    rest = normalize_rest(rest)

    Enum.any?(
      [
        "phx-click",
        :"phx-click",
        "phx-submit",
        :"phx-submit",
        "phx-change",
        :"phx-change",
        "phx-hook",
        :"phx-hook"
      ],
      &Map.has_key?(rest, &1)
    )
  end

  # Static class maps so Tailwind JIT sees full class names (dynamic bg-#{color}-700 is not purged).
  defp button_solid_color_classes do
    %{
      "blue" =>
        "bg-blue-700 hover:bg-blue-800 text-zinc-100 active:text-zinc-100/80 active:scale-[0.98] active:transition-none",
      "red" =>
        "bg-red-700 hover:bg-red-800 text-zinc-100 active:text-zinc-100/80 active:scale-[0.98] active:transition-none",
      "green" =>
        "bg-green-700 hover:bg-green-800 text-zinc-100 active:text-zinc-100/80 active:scale-[0.98] active:transition-none",
      "amber" =>
        "bg-amber-700 hover:bg-amber-800 text-zinc-100 active:text-zinc-100/80 active:scale-[0.98] active:transition-none",
      "zinc" =>
        "bg-zinc-700 hover:bg-zinc-800 text-zinc-100 active:text-zinc-100/80 active:scale-[0.98] active:transition-none",
      "teal" =>
        "bg-teal-700 hover:bg-teal-800 text-zinc-100 active:text-zinc-100/80 active:scale-[0.98] active:transition-none"
    }
  end

  defp button_outline_color_classes do
    %{
      "blue" =>
        "border border-blue-200 hover:bg-blue-50 text-blue-700 active:text-blue-700 bg-transparent",
      "red" =>
        "border border-red-200 hover:bg-red-50 text-red-700 active:text-red-700 bg-transparent",
      "green" =>
        "border border-green-200 hover:bg-green-50 text-green-700 active:text-green-700 bg-transparent",
      "amber" =>
        "border border-amber-200 hover:bg-amber-100 text-amber-700 active:text-amber-700 bg-transparent",
      "zinc" =>
        "border border-zinc-200 hover:bg-zinc-50 text-zinc-700 active:text-zinc-700 bg-transparent",
      "teal" =>
        "border border-teal-200 hover:bg-teal-50 text-teal-700 active:text-teal-700 bg-transparent"
    }
  end

  @doc """
  Renders a toggle (switch) control with an optional label.

  Uses a full-size overlay checkbox with Tailwind's `peer` and `peer-checked:` so the track
  and knob (via `after:` pseudo-element) animate when toggled. The input receives the click
  so it toggles immediately; pass phx-click/phx-target on the input to sync with the server.

  ## Examples

      <.toggle
        id="tickets-tbd"
        checked={@event.tickets_tbd}
        label="Tickets Coming Soon"
        phx-click="toggle-tickets-tbd"
        phx-target={@myself}
      />

  """
  attr :id, :string, default: nil
  attr :checked, :boolean, required: true, doc: "Whether the toggle is on"

  attr :label, :string,
    default: nil,
    doc: "Optional label text shown next to the toggle"

  attr :class, :string,
    default: nil,
    doc: "Additional classes for the wrapper label"

  attr :rest, :global, include: ~w(phx-click phx-target disabled tabindex)

  def toggle(assigns) do
    ~H"""
    <label
      id={@id}
      class={[
        "relative inline-flex items-center cursor-pointer select-none p-2 gap-3",
        @class
      ]}
      {@rest}
    >
      <span
        :if={@label}
        class={[
          "text-sm font-semibold",
          if(@checked, do: "text-green-700", else: "text-zinc-400")
        ]}
        style="transition: color 0.3s ease-in-out;"
      >
        {@label}
      </span>
      <span
        class={[
          "inline-flex items-center flex-shrink-0 w-14 h-8 p-1 rounded-full",
          if(@checked, do: "bg-green-500", else: "bg-zinc-300")
        ]}
        style="transition: background-color 0.3s ease-in-out;"
      >
        <span
          class="block w-6 h-6 bg-white rounded-full shadow-md"
          style={"transform: translateX(#{if @checked, do: "1.5rem", else: "0"}); transition: transform 0.3s ease-in-out;"}
        >
        </span>
      </span>
    </label>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :subtitle, :string, default: ""
  attr :icon, :string
  attr :footer, :string, default: nil

  attr :growing_field_size, :string, default: "small"

  attr :type, :string,
    default: "text",
    values:
      ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time url week checkgroup
               country-select large-radio phone-input date-text text-growing password-toggle otp)

  attr :field, Phoenix.HTML.FormField,
    doc:
      "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"

  attr :options, :list,
    doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"

  attr :multiple, :boolean,
    default: false,
    doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include:
      ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  slot :inner_block

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn ->
      if assigns.multiple, do: field.name <> "[]", else: field.name
    end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox", value: value} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", value)
      end)

    ~H"""
    <div>
      <label class="flex items-start gap-3 text-sm leading-6 text-zinc-600 cursor-pointer py-1">
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="mt-0.5 rounded border-zinc-300 text-zinc-900 focus:ring-0 w-5 h-5 flex-shrink-0"
          {@rest}
        />
        <span class="flex-1">{@label}</span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "radio"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <input
        type="radio"
        id={@id}
        name={@name}
        value={@value}
        checked={@checked}
        class="rounded border-zinc-300 text-zinc-900 focus:ring-0"
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "large-radio"} = assigns) do
    ~H"""
    <input
      type="radio"
      id={@id}
      name={@name}
      value={@value}
      checked={@checked}
      class="hidden peer"
      {@rest}
      required
    />
    <label
      for={@id}
      class="inline-flex items-center transition duration-150 ease-in-out justify-between w-full p-5 bg-white border rounded cursor-pointer text-zinc-500 border-zinc-200 peer-checked:border-blue-600 peer-checked:text-blue-600 hover:text-zinc-600 hover:bg-zinc-100 h-full"
    >
      <div class="flex flex-row">
        <div class="text-center items-center flex mr-4">
          <.icon name={"hero-" <> @icon} class="w-8 h-8" />
        </div>
        <div class="block">
          <div class="w-full font-semibold text-md text-zinc-800">
            {@label}
          </div>
          <div class="w-full text-sm text-zinc-600">{@subtitle}</div>
          <div :if={@footer != nil} class="w-full text-sm font-semibold pt-2">
            {@footer}
          </div>
        </div>
      </div>
    </label>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div>
      <.label :if={@label != ""} for={@id}>{@label}</.label>
      <select
        id={@id}
        name={@name}
        class={[
          "block w-full h-10 min-w-30 bg-white border rounded shadow-sm border-zinc-300 focus:border-zinc-400 focus:ring-0 sm:text-sm",
          if(@label != "", do: "mt-2", else: "")
        ]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "country-select"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <select
        id={@id}
        name={@name}
        class="block w-full mt-2 h-11 bg-white border rounded shadow-sm border-zinc-300 focus:border-zinc-400 focus:ring-0 sm:text-sm text-zinc-800"
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(
          Enum.map(
            LivePhone.Country.list(["US", "SE", "FI", "DK", "NO", "IS"]),
            fn x ->
              {x.name, x.code}
            end
          ),
          @value
        )}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "mt-2 block w-full rounded text-zinc-800 focus:ring-0 sm:text-sm sm:leading-6 min-h-[6rem]",
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "checkgroup"} = assigns) do
    ~H"""
    <fieldset class="text-sm">
      <legend class="block text-sm font-semibold leading-6 text-zinc-800">
        {@label}
      </legend>
      <div class="w-full bg-white rounded text-left cursor-default focus:outline-none focus:ring-1 focus:ring-blue-500 focus:border-blue-500 sm:text-sm">
        <div class="grid grid-cols-1 gap-1 text-sm items-baseline">
          <div :for={{label, value} <- @options} class="flex items-center">
            <label for={"#{@name}-#{value}"} class="font-medium text-zinc-700 py-1">
              <input
                type="checkbox"
                id={"#{@name}-#{value}"}
                name={@name}
                value={value}
                checked={
                  @value &&
                    Enum.any?(@value, fn v -> to_string(v) == to_string(value) end)
                }
                class="mr-2 h-4 w-4 rounded border-zinc-300 text-blue-600 focus:ring-blue-400 transition duration-150 ease-in-out"
                {@rest}
              />
              {label}
            </label>
          </div>
        </div>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </fieldset>
    """
  end

  def input(%{type: "phone-input"} = assigns) do
    ~H"""
    <div>
      <.label for={"live_phone-tel-" <> @id}>{@label}</.label>
      <.live_component
        module={LivePhone}
        id={@id}
        form={assigns[:form]}
        field={@field}
        tabindex={0}
        name={@name}
        value={@value}
        preferred={["US", "SE", "FI", "NO", "IS", "DK"]}
        class={[
          @errors == [] && "border-zinc-300 focus:border-zinc-400",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "date-text"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <div class="relative">
        <input
          type="date"
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value("date", @value)}
          class={[
            "mt-2 block w-full rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
            @errors == [] && "border-zinc-300 focus:border-zinc-400",
            @errors != [] && "border-rose-400 focus:border-rose-400"
          ]}
          placeholder="YYYY-MM-DD"
          pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
          title="Date format: YYYY-MM-DD"
          {@rest}
        />
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "text-growing"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        phx-hook="GrowingInput"
        growing-input-size={@growing_field_size}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "text-icon"} = assigns) do
    ~H"""
    <div>
      <.label for={@id}>{@label}</.label>

      <div class="relative">
        <div class="absolute inset-y-0 start-0 flex items-center ps-3 pointer-events-none">
          {render_slot(@inner_block)}
        </div>
        <input
          type="text"
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            "mt-2 block w-full ps-7 rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
            @errors == [] && "border-zinc-300 focus:border-zinc-400",
            @errors != [] && "border-rose-400 focus:border-rose-400"
          ]}
          {@rest}
        />
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "otp"} = assigns) do
    # Generate id from name if not provided
    id =
      assigns.id || assigns.name ||
        "input-#{System.unique_integer([:positive])}"

    assigns = assign(assigns, :id, id)

    ~H"""
    <div>
      <.label :if={@label} for={@id}>{@label}</.label>

      <div class="flex gap-x-3 mt-1" data-otp-input="">
        <%= for i <- 0..5 do %>
          <input
            type="text"
            name={"#{@name}[#{i}]"}
            id={"#{@id}_#{i}"}
            maxlength="1"
            class="block w-12 h-12 text-center border-zinc-200 rounded sm:text-sm focus:scale-110 focus:border-blue-600 focus:ring-blue-600 disabled:opacity-50 disabled:pointer-events-none"
            data-otp-input-item=""
            {@rest}
          />
        <% end %>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Hidden inputs - no label needed
  def input(%{type: "hidden"} = assigns) do
    # Generate id from name if not provided
    id =
      assigns.id || assigns.name ||
        "input-#{System.unique_integer([:positive])}"

    assigns = assign(assigns, :id, id)

    ~H"""
    <input
      type="hidden"
      name={@name}
      id={@id}
      value={Phoenix.HTML.Form.normalize_value(@type, @value)}
      {@rest}
    />
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    # Generate id from name if not provided
    id =
      assigns.id || assigns.name ||
        "input-#{System.unique_integer([:positive])}"

    # Handle password-toggle type
    {type, is_password_toggle} =
      case assigns.type do
        "password-toggle" -> {"password", true}
        other -> {other, false}
      end

    assigns =
      assigns
      |> assign(:id, id)
      |> assign(:type, type)
      |> assign(:is_password_toggle, is_password_toggle)

    ~H"""
    <div>
      <.label :if={@label} for={@id}>{@label}</.label>

      <div class={["relative", @is_password_toggle && ""]}>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          autocomplete={@is_password_toggle && "current-password"}
          class={[
            "mt-2 block w-full rounded text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
            @is_password_toggle && "pr-10",
            @errors == [] && "border-zinc-300 focus:border-zinc-400",
            @errors != [] && "border-rose-400 focus:border-rose-400"
          ]}
          {@rest}
        />

        <button
          :if={@is_password_toggle}
          type="button"
          class="absolute inset-y-0 right-0 flex items-center pr-3 cursor-pointer password-toggle-btn"
          data-target={"##{@id}"}
          aria-label="Show password"
          aria-pressed="false"
        >
          <.icon
            name="hero-eye-solid"
            class="h-5 w-5 text-zinc-400 hover:text-zinc-600"
          />
        </button>
      </div>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField,
    doc:
      "a form field struct retrieved from the form, for example: @form[:email]"

  attr :options, :list, doc: "the options for the radio buttons in the fieldset"
  attr :checked_value, :string, doc: "the currently checked value"

  def radio_fieldset(%{field: %Phoenix.HTML.FormField{}} = assigns) do
    ~H"""
    <div>
      <ul class="grid w-full gap-6 md:grid-cols-2">
        <li :for={{_, values} <- @options} class="flex flex-col">
          <.input
            field={@field}
            id={"#{@field.id}_#{values[:option]}"}
            type="large-radio"
            label={String.capitalize(values[:option])}
            value={values[:option]}
            checked={
              @checked_value == values[:option] ||
                @field.value == String.to_atom(values[:option])
            }
            subtitle={values[:subtitle]}
            icon={values[:icon]}
            footer={values[:footer]}
          />
        </li>
      </ul>
    </div>
    """
  end

  @doc """
  Generate a checkbox group for multi-select.
  """
  attr :id, :any
  attr :name, :any
  attr :label, :string, default: nil

  attr :field, Phoenix.HTML.FormField,
    doc:
      "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list

  attr :options, :list,
    doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"

  attr :rest, :global, include: ~w(disabled form readonly)
  attr :class, :string, default: nil

  def checkgroup(assigns) do
    new_assigns =
      assigns
      |> assign(:multiple, true)
      |> assign(:type, "checkgroup")

    input(new_assigns)
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-semibold leading-6 text-zinc-800">
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="field-error flex gap-3 mt-3 text-sm leading-6 text-rose-600">
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @min_date Date.utc_today() |> Date.add(-365)

  attr(:id, :string, required: true)
  attr(:label, :string, required: true)

  attr(:start_date_field, :any,
    doc:
      "a %Phoenix.HTML.Form{}/field name tuple, for example: @form[:start_date]"
  )

  attr(:end_date_field, :any,
    doc:
      "a %Phoenix.HTML.Form{}/field name tuple, for example: @form[:end_date]"
  )

  attr(:required, :boolean, default: false)
  attr(:readonly, :boolean, default: false)
  attr(:disabled, :boolean, default: false)
  attr(:min, :any, default: @min_date, doc: "the earliest date that can be set")
  attr(:max, :any, default: nil, doc: "the latest date that can be set")
  attr(:errors, :list, default: [])
  attr(:form, :any)
  attr(:date_tooltips, :map, default: %{})
  attr(:property, :atom, default: nil)
  attr(:today, :any, default: nil)
  attr(:seasons, :list, default: nil)

  attr(:allow_saturdays, :boolean,
    default: false,
    doc: "Allow Saturday selection (default: false for booking restrictions)"
  )

  attr(:max_nights, :integer,
    default: 4,
    doc: "Maximum nights allowed for the selected date range"
  )

  attr(:checkout_date_tooltips, :map,
    default: %{},
    doc: "Unavailable checkout dates keyed by ISO date when selecting check-out"
  )

  def date_range_picker(assigns) do
    ~H"""
    <.live_component
      module={YscWeb.Components.DateRangePicker}
      label={@label}
      id={@id}
      form={@form}
      start_date_field={@start_date_field}
      end_date_field={@end_date_field}
      required={@required}
      readonly={@readonly}
      disabled={@disabled}
      is_range?
      min={@min}
      max={@max}
      date_tooltips={@date_tooltips}
      checkout_date_tooltips={@checkout_date_tooltips}
      property={@property}
      today={@today}
      seasons={@seasons}
      allow_saturdays={@allow_saturdays}
      max_nights={@max_nights}
    />
    <div :if={Phoenix.Component.used_input?(@start_date_field)}>
      <.error :for={msg <- @start_date_field.errors}>
        {FormHelpers.format_form_error(msg)}
      </.error>
    </div>
    <div :if={Phoenix.Component.used_input?(@end_date_field)}>
      <.error :for={msg <- @end_date_field.errors}>
        {FormHelpers.format_form_error(msg)}
      </.error>
    </div>
    """
  end

  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[
      @actions != [] && "flex items-center justify-between gap-6",
      @class
    ]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-zinc-800">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-zinc-600">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc ~S"""
  Renders an alert banner with icon, message, and optional action button.

  ## Examples

      <.alert_banner
        type="warning"
        icon="hero-exclamation-triangle"
        title="Application Under Review"
      >
        Your membership application is currently being reviewed.
      </.alert_banner>

      <.alert_banner
        type="warning"
        icon="hero-exclamation-triangle"
        title="Membership Required"
        action_label="Manage Membership"
        action_path={~p"/users/membership"}
      >
        To access events, you need an active membership.
      </.alert_banner>
  """
  attr :type, :string,
    default: "info",
    doc: "alert type: info, warning, error, success, orange"

  attr :icon, :string, required: true, doc: "heroicon name"
  attr :title, :string, default: nil, doc: "optional title text"
  attr :action_label, :string, default: nil, doc: "optional action button label"
  attr :action_path, :string, default: nil, doc: "optional action button path"

  attr :action_class, :string,
    default: nil,
    doc: "optional action button custom classes"

  slot :inner_block, required: true, doc: "the main message content"

  def alert_banner(assigns) do
    type_classes = %{
      "info" => "bg-blue-50 border-blue-400 text-blue-700",
      "warning" => "bg-yellow-50 border-yellow-400 text-yellow-700",
      "error" => "bg-red-50 border-red-400 text-red-700",
      "success" => "bg-green-50 border-green-400 text-green-700",
      "orange" => "bg-orange-50 border-orange-400 text-orange-700"
    }

    icon_classes = %{
      "info" => "text-blue-400",
      "warning" => "text-yellow-400",
      "error" => "text-red-400",
      "success" => "text-green-400",
      "orange" => "text-orange-400"
    }

    button_classes = %{
      "info" => "bg-blue-600 hover:bg-blue-700 focus:ring-blue-500",
      "warning" => "bg-yellow-600 hover:bg-yellow-700 focus:ring-yellow-500",
      "error" => "bg-red-600 hover:bg-red-700 focus:ring-red-500",
      "success" => "bg-green-600 hover:bg-green-700 focus:ring-green-500",
      "orange" => "bg-orange-600 hover:bg-orange-700 focus:ring-orange-500"
    }

    base_classes = type_classes[assigns.type] || type_classes["info"]
    icon_color = icon_classes[assigns.type] || icon_classes["info"]
    button_color = button_classes[assigns.type] || button_classes["info"]

    assigns =
      assigns
      |> assign(:base_classes, base_classes)
      |> assign(:icon_color, icon_color)
      |> assign(:button_color, button_color)

    ~H"""
    <div class={"border-l-4 p-4 #{@base_classes}"}>
      <div class={"flex items-start max-w-screen-xl mx-auto md:px-4 #{if @action_label, do: "", else: "items-center"}"}>
        <div class="flex-shrink-0 pt-1">
          <.icon name={@icon} class={"h-8 w-8 #{@icon_color}"} />
        </div>
        <div class="px-4 flex-1">
          <p class="text-sm">
            <strong :if={@title}>{@title}:</strong>
            {render_slot(@inner_block)}
          </p>
          <div :if={@action_label} class="flex flex-col sm:flex-row gap-2 mt-3">
            <.link
              navigate={@action_path}
              class={[
                "inline-flex items-center px-4 py-2 text-sm font-semibold text-white rounded-md focus:outline-none focus:ring-2 focus:ring-offset-2 transition-colors duration-200",
                @button_color,
                @action_class
              ]}
            >
              <.icon name="hero-credit-card" class="w-5 h-5 me-2" />
              {@action_label}
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true

  attr :row_id, :any,
    default: nil,
    doc: "the function for generating the row id"

  attr :row_click, :any,
    default: nil,
    doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc:
      "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action,
    doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="px-4 overflow-y-auto sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-11 sm:w-full">
        <thead class="text-sm leading-6 text-left text-zinc-500">
          <tr>
            <th :for={col <- @col} class="p-0 pb-4 pr-6 font-normal">
              {col[:label]}
            </th>
            <th class="relative p-0 pb-4">
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="relative text-sm leading-6 border-t divide-y divide-zinc-100 border-zinc-200 text-zinc-700"
        >
          <tr
            :for={row <- @rows}
            id={@row_id && @row_id.(row)}
            class="group hover:bg-zinc-50"
          >
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["relative p-0", @row_click && "hover:cursor-pointer"]}
            >
              <div class="block py-4 pr-6">
                <span class="absolute right-0 -inset-y-px -left-4 group-hover:bg-zinc-50 sm:rounded-l-xl" />
                <span class={["relative", i == 0 && "font-semibold text-zinc-900"]}>
                  {render_slot(col, @row_item.(row))}
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative p-0 w-14">
              <div class="relative py-4 text-sm font-medium text-right whitespace-nowrap">
                <span class="absolute left-0 -inset-y-px -right-4 group-hover:bg-zinc-50 sm:rounded-r-xl" />
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                >
                  {render_slot(action, @row_item.(row))}
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title"><%= @post.title %></:item>
        <:item title="Views"><%= @post.views %></:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-zinc-100">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="flex-none w-1/4 text-zinc-500">{item.title}</dt>
          <dd class="text-zinc-700">{render_slot(item)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div>
      <.link
        navigate={@navigate}
        class="text-sm font-semibold leading-6 text-zinc-600 hover:text-zinc-800 rounded hover:bg-zinc-100 p-2"
      >
        <.icon name="hero-arrow-left-solid" class="w-3 h-3 -mt-0.5" />
        {render_slot(@inner_block)}
      </.link>
    </div>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from your `assets/vendor/heroicons` directory and bundled
  within your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="w-3 h-3 ml-1 animate-spin" />
  """
  attr :name, :string, required: true
  attr :id, :string, default: nil
  attr :class, :any, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span :if={@id != nil} id={@id} class={[@name, @class]} />
    <span :if={@id == nil} class={[@name, @class]} />
    """
  end

  attr :name, :string, required: true
  attr :class, :string, default: nil

  def flash_toast_icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <.icon name={@name} class={["w-5 h-5 flex-shrink-0 me-1", @class]} />
    """
  end

  @doc false
  def flash_toast_icon_success(assigns) do
    ~H"""
    <.flash_toast_icon name="hero-check-circle" class="text-green-500" />
    """
  end

  @doc false
  def flash_toast_icon_error(assigns) do
    ~H"""
    <.flash_toast_icon name="hero-x-circle" class="text-red-500" />
    """
  end

  @doc false
  def flash_toast_icon_warning(assigns) do
    ~H"""
    <.flash_toast_icon name="hero-exclamation-triangle" class="text-yellow-500" />
    """
  end

  @doc false
  def flash_toast_icon_clock(assigns) do
    ~H"""
    <.flash_toast_icon name="hero-clock" class="text-blue-500" />
    """
  end

  @doc false
  def flash_toast_icon_payment(assigns) do
    ~H"""
    <.flash_toast_icon name="hero-credit-card" class="text-indigo-500" />
    """
  end

  @doc false
  def flash_toast_icon_calendar(assigns) do
    ~H"""
    <.flash_toast_icon name="hero-calendar-days" class="text-sky-500" />
    """
  end

  @doc false
  def flash_toast_icon_mail(assigns) do
    ~H"""
    <.flash_toast_icon name="hero-envelope" class="text-violet-500" />
    """
  end

  @doc false
  def flash_toast_icon_shield(assigns) do
    ~H"""
    <.flash_toast_icon name="hero-shield-check" class="text-emerald-500" />
    """
  end

  @doc """
  Renders a fixed red banner at the bottom when an admin is impersonating a user.
  Shows the impersonated user's name and email and a "Stop Impersonating" button.
  """
  attr :impersonating?, :boolean, required: true
  attr :impersonated_user_name, :string, required: true
  attr :impersonated_user_email, :string, required: true

  def impersonation_banner(assigns) do
    ~H"""
    <div
      :if={@impersonating?}
      class="fixed bottom-0 left-0 right-0 z-[9999] bg-red-600 text-white shadow-lg"
    >
      <div class="container mx-auto px-4 py-3 flex items-center justify-between">
        <div class="flex items-center gap-3">
          <.icon name="hero-exclamation-triangle" class="w-6 h-6 flex-shrink-0" />
          <div>
            <p class="font-bold text-sm">IMPERSONATING USER</p>
            <p class="text-xs">
              Viewing as: {@impersonated_user_name} ({@impersonated_user_email})
            </p>
          </div>
        </div>
        <form
          id="stop-impersonation-form"
          action={~p"/admin/stop-impersonation"}
          method="post"
          class="inline m-0"
        >
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
          <button
            type="submit"
            class="bg-white text-red-600 px-4 py-2 rounded font-semibold hover:bg-red-50 transition-colors"
          >
            Stop Impersonating
          </button>
        </form>
      </div>
    </div>
    """
  end

  attr :country, :string, required: true
  attr :class, :string, default: nil

  def flag(%{country: "fi-" <> _} = assigns) do
    ~H"""
    <span class={["fi", @country, @class]} />
    """
  end

  attr :id, :string, required: true
  attr :class, :string, default: nil
  attr :right, :boolean, default: false
  attr :mobile, :boolean, default: false
  attr :wide, :boolean, default: false
  slot :button_block, required: true
  slot :inner_block, required: true

  def dropdown(assigns) do
    ~H"""
    <div class="relative">
      <button
        type="button"
        id={"#{@id}Link"}
        data-dropdown-toggle={@id}
        class={"group flex items-center justify-between w-full px-3 py-2 font-bold transition duration-200 ease-in-out rounded lg:w-auto #{@class}"}
        phx-click={toggle_dropdown("##{@id}")}
      >
        {render_slot(@button_block)}
      </button>
      <!-- Dropdown menu -->
      <div
        id={@id}
        class={[
          "z-[110] hidden mt-1 font-normal bg-white divide-y rounded divide-zinc-100 shadow w-52 wide:w-72",
          @right && "right-0",
          !@right && "left-0",
          @mobile && "block lg:absolute shadow-none lg:shadow",
          !@mobile && "absolute shadow",
          @wide && "wide"
        ]}
        phx-click-away={toggle_dropdown("##{@id}")}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @board_position_to_title_lookup %{
    president: "President",
    vice_president: "Vice President",
    secretary: "Secretary",
    treasurer: "Treasurer",
    clear_lake_cabin_master: "Clear Lake Cabin Master",
    tahoe_cabin_master: "Tahoe Cabin Master",
    event_director: "Event Director",
    member_outreach: "Member Outreach & Events",
    membership_director: "Membership Director"
  }

  attr :user, :any,
    default: nil,
    doc:
      "User struct or map; when provided, derives all user fields automatically"

  attr :email, :string, default: nil
  attr :title, :string, required: false, default: nil
  attr :user_id, :string, default: nil
  attr :most_connected_country, :string, default: nil
  attr :first_name, :string, default: nil
  attr :last_name, :string, default: nil
  attr :right, :boolean, default: false
  attr :show_subtitle, :boolean, default: true
  attr :class, :string, default: ""
  attr :avatar_url, :string, default: nil

  def user_card(assigns) do
    assigns = derive_user_card_assigns(assigns)

    subtitle =
      if assigns[:title] != nil do
        "YSC #{Map.get(@board_position_to_title_lookup,
        assigns[:title],
        String.capitalize("#{assigns[:title]}"))}"
      else
        String.downcase(assigns[:email] || "")
      end

    assigns = assign(assigns, :subtitle, subtitle)

    first_name = Ysc.title_case(assigns[:first_name] || "")
    last_name = Ysc.title_case(assigns[:last_name] || "")

    full_name =
      cond do
        first_name != "" && last_name != "" -> "#{first_name} #{last_name}"
        first_name != "" -> first_name
        last_name != "" -> last_name
        true -> assigns[:email] || "Unknown User"
      end

    display_name =
      if String.length(full_name) > 30 do
        String.slice(full_name, 0, 27) <> "..."
      else
        full_name
      end

    assigns = assign(assigns, :display_name, display_name)

    ~H"""
    <div class={"flex items-center whitespace-nowrap h-10 #{@class}"}>
      <.user_avatar_image
        user={@user}
        email={@email}
        user_id={@user_id}
        country={@most_connected_country}
        avatar_url={@avatar_url}
        class={
          Enum.join(
            [
              "w-10 h-10 rounded-full ring-2 ring-zinc-200 ring-offset-2 ring-offset-white",
              @right && "order-2"
            ],
            " "
          )
        }
      />
      <div class={[
        @right && "order-1 pe-3",
        !@right && "ps-3"
      ]}>
        <div class="text-sm font-semibold text-zinc-800 text-left">
          {@display_name}
        </div>
        <div :if={@show_subtitle} class="font-normal text-sm text-zinc-500">
          {@subtitle}
        </div>
      </div>
    </div>
    """
  end

  defp derive_user_card_assigns(%{user: user} = assigns)
       when not is_nil(user) do
    assigns
    |> assign(:email, Map.get(user, :email, ""))
    |> assign(:user_id, to_string(Map.get(user, :id, "0")))
    |> assign(
      :most_connected_country,
      Map.get(user, :most_connected_country, "SE")
    )
    |> assign(:first_name, Map.get(user, :first_name, ""))
    |> assign(:last_name, Map.get(user, :last_name, ""))
    |> assign(
      :avatar_url,
      assigns[:avatar_url] ||
        Ysc.Avatars.resolve_user_avatar_url(user, :profile)
    )
  end

  defp derive_user_card_assigns(assigns), do: assigns

  attr :user, :any,
    default: nil,
    doc:
      "User struct or map; when provided, derives all user fields automatically"

  attr :user_id, :string, default: nil
  attr :email, :string, default: nil
  attr :first_name, :string, default: nil
  attr :last_name, :string, default: nil
  attr :most_connected_country, :string, default: nil
  attr :avatar_url, :string, default: nil
  slot :inner_block, required: true

  def user_avatar(assigns) do
    assigns = derive_user_card_assigns(assigns)

    ~H"""
    <div class="relative">
      <button
        data-dropdown-toggle="avatar-menu"
        id="avatar-menu-link"
        class="flex flex-row rounded hover:bg-zinc-100 pl-3"
        phx-click={show_dropdown("#avatar-menu")}
      >
        <.user_card
          user={@user}
          email={@email}
          user_id={@user_id}
          most_connected_country={@most_connected_country}
          first_name={@first_name}
          last_name={@last_name}
          avatar_url={@avatar_url}
          right={true}
          show_subtitle={false}
        />
      </button>
      <!-- Dropdown menu -->
      <div
        id="avatar-menu"
        class="absolute z-[110] hidden w-60 mt-0 font-normal bg-white divide-y rounded shadow divide-zinc-100 right-4 mt-1"
        phx-click-away={hide_dropdown("#avatar-menu")}
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :toggle_id, :string, required: true
  attr :current_user, :any, required: true
  slot :desktop_content, required: true
  slot :mobile_content, required: true
  slot :cta_section

  def hamburger_menu(assigns) do
    ~H"""
    <div class="flex w-full items-center justify-between lg:justify-between">
      <%!-- Mobile: Hamburger button --%>
      <button
        type="button"
        class="hamburger-btn nav-link inline-flex items-center justify-center h-10 p-2 transition ease-in-out rounded lg:hidden focus:outline-none duration-400 text-zinc-900 hover:bg-zinc-200"
        aria-controls={@toggle_id}
        aria-expanded="false"
        phx-click={show_mobile_menu(@toggle_id)}
      >
        <div id={"#{@toggle_id}-hamburger"} class="nav-icon">
          <span></span>
          <span></span>
          <span></span>
          <span></span>
        </div>
        <span class="menu-label ms-4 font-semibold">
          Menu
        </span>
      </button>

      <%!-- Desktop: Navigation links inline --%>
      <div class="hidden lg:flex lg:items-center lg:space-x-8">
        {render_slot(@desktop_content)}
      </div>

      <%!-- CTA section (visible on both mobile and desktop) --%>
      <div id="cta-section" class="flex items-center">
        {render_slot(@cta_section)}
      </div>
    </div>

    <%!-- Mobile: Slide-in menu overlay --%>
    <div
      id={"#{@toggle_id}-overlay"}
      class="mobile-menu-overlay fixed inset-0 bg-black/50 z-[9998] hidden lg:hidden"
      phx-click={hide_mobile_menu(@toggle_id)}
      aria-hidden="true"
    />

    <%!-- Mobile: Slide-in menu panel --%>
    <div
      id={@toggle_id}
      class="mobile-menu-panel fixed top-0 left-0 h-full w-80 max-w-[85vw] bg-white z-[9999] transform -translate-x-full transition-transform duration-300 ease-in-out lg:hidden overflow-y-auto shadow-2xl"
    >
      <%!-- Menu header with logo and close button --%>
      <div class="flex items-center justify-between p-4 border-b border-zinc-200">
        <.link
          navigate="/"
          class="flex items-center gap-3"
          phx-click={hide_mobile_menu(@toggle_id)}
        >
          <.ysc_logo no_circle={true} class="h-14 w-14" width={56} height={56} />
          <span class="text-lg font-bold text-zinc-900">YSC.org</span>
        </.link>
        <button
          type="button"
          class="p-2 rounded-md text-zinc-500 hover:bg-zinc-100 hover:text-zinc-900 transition-colors"
          phx-click={hide_mobile_menu(@toggle_id)}
          aria-label="Close menu"
        >
          <.icon name="hero-x-mark" class="w-6 h-6" />
        </button>
      </div>

      <%!-- Menu content --%>
      <div class="mobile-menu-content p-4">
        {render_slot(@mobile_content)}
      </div>
    </div>
    """
  end

  defp show_mobile_menu(id) do
    JS.add_class("open", to: "##{id}-hamburger")
    |> JS.remove_class("hidden", to: "##{id}-overlay")
    |> JS.remove_class("-translate-x-full", to: "##{id}")
    |> JS.add_class("translate-x-0", to: "##{id}")
    |> JS.add_class("overflow-hidden", to: "body")
  end

  defp hide_mobile_menu(id) do
    JS.remove_class("open", to: "##{id}-hamburger")
    |> JS.add_class("hidden", to: "##{id}-overlay")
    |> JS.add_class("-translate-x-full", to: "##{id}")
    |> JS.remove_class("translate-x-0", to: "##{id}")
    |> JS.remove_class("overflow-hidden", to: "body")
  end

  attr :type, :string, default: "default"
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={[
      "inline-block text-xs font-medium me-2 px-2 py-1 rounded whitespace-nowrap #{@class}",
      @type == "sky" && "bg-sky-100 text-sky-800",
      @type == "green" && "bg-green-100 text-green-800",
      @type == "yellow" && "bg-yellow-100 text-yellow-800",
      @type == "red" && "bg-red-100 text-red-800",
      @type == "dark" && "bg-zinc-100 text-zinc-800",
      @type == "zinc" && "bg-zinc-100 text-zinc-800",
      @type == "default" && "bg-blue-100 text-blue-800"
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  attr :class, :string, default: nil
  attr :tooltip_text, :string, required: true

  attr :max_width, :string,
    default: "max-w-xl",
    doc:
      "Maximum width class (e.g., max-w-xs, max-w-sm, max-w-md, max-w-lg, max-w-xl, max-w-2xl, max-w-3xl, max-w-4xl)"

  attr :text_align, :string,
    default: "text-center",
    values: ~w(text-left text-center text-right),
    doc: "Text alignment for the tooltip content"

  slot :inner_block, required: true

  @spec tooltip(map()) :: Phoenix.LiveView.Rendered.t()
  def tooltip(assigns) do
    ~H"""
    <div>
      <div class="group relative">
        {render_slot(@inner_block)}
        <span
          role="tooltip"
          class={[
            "absolute transition-opacity mt-10 top-0 left-1/2 transform -translate-x-1/2 duration-200 opacity-0 pointer-events-none z-50 text-xs font-medium text-zinc-100 bg-zinc-900 rounded-md shadow-sm px-4 py-2 block tooltip group-hover:opacity-100 group-hover:pointer-events-auto whitespace-normal",
            @max_width,
            @text_align
          ]}
        >
          {@tooltip_text}
        </span>
      </div>
    </div>
    """
  end

  attr :class, :string, default: nil
  slot :inner_block, required: true
  slot :tooltip_body, required: true

  def tooltip_special(assigns) do
    ~H"""
    <div class="group relative">
      {render_slot(@inner_block)}
      <span
        role="tooltip"
        class="absolute transition-opacity mt-10 top-0 left-1/2 transform -translate-x-1/2 w-80 duration-200 opacity-0 pointer-events-none z-50 text-xs font-medium text-zinc-100 bg-zinc-900 rounded-md shadow-sm px-3 py-2 inline-block text-left tooltip group-hover:opacity-100 group-hover:pointer-events-auto"
      >
        {render_slot(@tooltip_body)}
      </span>
    </div>
    """
  end

  attr :event, :any, required: true
  attr :sold_out, :boolean, default: false
  attr :selling_fast, :boolean, default: false

  def event_badge(assigns) do
    assigns =
      assigns
      |> assign(:event, assigns.event)
      |> assign(
        :badges,
        get_event_badges(assigns.event, assigns.sold_out, assigns.selling_fast)
      )

    ~H"""
    <div class="flex flex-wrap gap-2">
      <.badge :for={{type, text} <- @badges} type={type} class="text-xs font-medium">
        <.icon
          :if={text == "Going Fast!"}
          name="hero-bolt-solid"
          class="w-3 h-3 inline-block me-0.5 -mt-0.5"
        />
        {text}
      </.badge>
    </div>
    """
  end

  # Returns a list of {type, text} tuples for badges to display
  # Handles both Event structs and maps from queries
  defp get_event_badges(event, sold_out, selling_fast) when is_map(event) do
    # Check for cancelled state first - if cancelled, only show "Cancelled" badge
    state = Map.get(event, :state) || Map.get(event, "state")

    if state == :cancelled or state == "cancelled" do
      [{"red", "Cancelled"}]
    else
      # If sold out (and not cancelled), only show "Sold Out" badge
      if sold_out do
        [{"red", "Sold Out"}]
      else
        get_event_badges_continue(event, sold_out, selling_fast)
      end
    end
  end

  defp get_event_badges(event, true, _selling_fast) do
    # Check for cancelled state first - if cancelled, only show "Cancelled" badge
    state = Map.get(event, :state) || Map.get(event, "state")

    if state == :cancelled or state == "cancelled" do
      [{"red", "Cancelled"}]
    else
      [{"red", "Sold Out"}]
    end
  end

  defp get_event_badges(event, false, selling_fast) do
    # Check for cancelled state first - if cancelled, only show "Cancelled" badge
    state = Map.get(event, :state) || Map.get(event, "state")

    if state == :cancelled or state == "cancelled" do
      [{"red", "Cancelled"}]
    else
      get_event_badges_continue(event, false, selling_fast)
    end
  end

  defp get_event_badges(_, _, _), do: []

  defp get_event_badges_continue(event, sold_out, selling_fast) do
    # Check if published_at is nil (no badge for unpublished events)
    published_at =
      Map.get(event, :published_at) || Map.get(event, "published_at")

    if published_at == nil do
      []
    else
      get_event_badges_active(event, sold_out, selling_fast)
    end
  end

  defp get_event_badges_active(event, _sold_out, selling_fast) do
    badges = []

    # Add "Just Added" badge first if applicable (within 48 hours of publishing)
    published_at =
      Map.get(event, :published_at) || Map.get(event, "published_at")

    just_added_badge =
      case published_at do
        nil ->
          []

        pub_at ->
          if DateTime.diff(DateTime.utc_now(), pub_at, :hour) <= 48 do
            [{"green", "Just Added"}]
          else
            []
          end
      end

    badges = badges ++ just_added_badge

    # Add "Days Left" badge if applicable (1-3 days remaining)
    days_left = days_until_event_start(event)

    days_left_badge =
      if days_left != nil and days_left >= 1 and days_left <= 3 do
        text = "#{days_left} #{if days_left == 1, do: "day", else: "days"} left"
        [{"sky", text}]
      else
        []
      end

    badges = badges ++ days_left_badge

    # Add "Selling Fast!" badge if applicable (always show when true)
    selling_fast_badge =
      if selling_fast do
        [{"yellow", "Going Fast!"}]
      else
        []
      end

    badges = badges ++ selling_fast_badge
    badges
  end

  attr :event, :any, required: true
  attr :class, :string, default: nil
  attr :sold_out, :boolean, default: false
  attr :selling_fast, :boolean, default: false
  attr :variant, :string, default: "default"

  def event_card(assigns) do
    YscWeb.Components.Events.EventCard.event_card(assigns)
  end

  attr :post, :any, required: true
  attr :class, :string, default: nil
  attr :variant, :string, default: "default"

  def news_card(assigns) do
    YscWeb.Components.News.NewsCard.news_card(assigns)
  end

  # Helper function to calculate days until event starts
  # Handles both Event structs and maps (structs are maps in Elixir)
  defp days_until_event_start(event) when is_map(event) do
    start_date = Map.get(event, :start_date)
    start_time = Map.get(event, :start_time)

    if start_date == nil do
      nil
    else
      now = DateTime.utc_now()

      # Combine start_date and start_time to get the event datetime
      event_datetime = combine_date_time_for_event(start_date, start_time)

      # If we couldn't combine the datetime, return nil
      if event_datetime == nil do
        nil
      else
        # If event is in the past, return nil
        if DateTime.compare(now, event_datetime) == :gt do
          nil
        else
          # Calculate days difference using calendar days
          event_date_only = DateTime.to_date(event_datetime)
          now_date_only = DateTime.to_date(now)
          diff = Date.diff(event_date_only, now_date_only)
          max(0, diff)
        end
      end
    end
  end

  defp combine_date_time_for_event(date, time) do
    case {date, time} do
      {%DateTime{} = dt, %Time{} = t} ->
        naive_date = DateTime.to_naive(dt)
        date_part = NaiveDateTime.to_date(naive_date)
        naive_datetime = NaiveDateTime.new!(date_part, t)
        DateTime.from_naive!(naive_datetime, "Etc/UTC")

      {%DateTime{} = dt, nil} ->
        dt

      {date, time} when not is_nil(date) and not is_nil(time) ->
        NaiveDateTime.new!(date, time)
        |> DateTime.from_naive!("Etc/UTC")

      {date, nil} when not is_nil(date) ->
        if match?(%DateTime{}, date) do
          date
        else
          DateTime.from_naive!(
            NaiveDateTime.new!(date, ~T[00:00:00]),
            "Etc/UTC"
          )
        end

      _ ->
        nil
    end
  end

  attr :active_step, :integer, required: true
  attr :steps, :list, default: []

  @spec stepper(map()) :: Phoenix.LiveView.Rendered.t()
  def stepper(assigns) do
    assigns =
      assigns
      |> assign(:stepper_max_length, length(assigns.steps))

    ~H"""
    <ol class="flex items-center justify-between w-full px-2 py-2 text-sm font-medium text-center border rounded text-zinc-400 border-zinc-100 sm:px-4 sm:py-3 sm:text-base">
      <%= for {val, idx} <- Enum.with_index(@steps) do %>
        <li :if={idx != @active_step} class="shrink-0">
          <button
            phx-click="set-step"
            phx-value-step={idx}
            class="group flex items-center gap-x-2 leading-6 text-sm hover:text-blue-400 transition-colors duration-150 cursor-pointer"
          >
            <span class="flex items-center text-zinc-400 justify-center w-6 h-6 text-xs font-bold border rounded shrink-0 border-zinc-400 group-hover:bg-blue-50 group-hover:border-blue-300 group-hover:text-blue-400 transition-colors duration-150">
              {idx + 1}
            </span>
            <span class="hidden sm:inline mx-2">{val}</span>
            <.icon
              :if={idx + 1 < assigns[:stepper_max_length]}
              name="hero-chevron-right"
              class="w-4 h-4 sm:w-5 sm:h-5"
            />
          </button>
        </li>
        <li
          :if={idx == @active_step}
          class="flex items-center gap-x-2 leading-6 text-blue-800 text-sm min-w-0"
        >
          <span class="flex items-center text-zinc-100 justify-center w-6 h-6 text-xs font-bold bg-blue-600 border border-blue-600 rounded shrink-0">
            {idx + 1}
          </span>
          <span class="truncate mx-2 sm:truncate-none">{val}</span>
          <.icon
            :if={idx + 1 < assigns[:stepper_max_length]}
            name="hero-chevron-right"
            class="w-4 h-4 shrink-0 sm:w-5 sm:h-5"
          />
        </li>
      <% end %>
    </ol>
    """
  end

  attr :class, :string, default: nil
  attr :no_circle, :boolean, default: false
  attr :fetchpriority, :string, default: nil
  attr :width, :integer, required: true
  attr :height, :integer, required: true

  def ysc_logo(assigns) do
    ~H"""
    <picture :if={!@no_circle}>
      <source srcset={~p"/images/ysc_logo.webp"} type="image/webp" />
      <img
        class={["object-contain", @class]}
        src={~p"/images/ysc_logo.png"}
        alt="The Young Scandinavian Club Logo"
        width={@width}
        height={@height}
        fetchpriority={@fetchpriority}
      />
    </picture>
    <img
      :if={@no_circle}
      class={["object-contain", @class]}
      src={~p"/images/ysc_logo_no_circle.svg"}
      alt="The Young Scandinavian Club Logo"
      width={@width}
      height={@height}
      fetchpriority={@fetchpriority}
    />
    """
  end

  attr :viking, :integer, default: 4
  attr :title, :string, default: "Looks like this page is empty"
  attr :suggestion, :string, default: nil

  def empty_viking_state(assigns) do
    ~H"""
    <div class="text-center justify-center items-center w-full">
      <img
        class={[
          "w-60 mx-auto",
          Enum.member?([2, 4], @viking) && "rounded-full"
        ]}
        src={"/images/vikings/small/viking_#{@viking}.png"}
        alt="Looks like this page is empty"
      />
      <.header class="pt-8">
        {@title}
        <:subtitle>{@suggestion}</:subtitle>
      </.header>
    </div>
    """
  end

  attr :user, :any,
    default: nil,
    doc:
      "User struct or map; when provided, derives email/user_id/country/avatar_url automatically"

  attr :email, :string, default: nil
  attr :user_id, :string, default: nil
  attr :country, :string, default: nil
  attr :class, :string, default: ""
  attr :avatar_url, :string, default: nil

  attr :size, :atom,
    default: :profile,
    doc: "Avatar size variant (:thumb, :profile, :large)"

  def user_avatar_image(assigns) do
    assigns = derive_avatar_assigns(assigns)

    full_path =
      if is_binary(assigns[:avatar_url]) and assigns[:avatar_url] != "" do
        assigns[:avatar_url]
      else
        user_id = assigns[:user_id] || "0"
        country = assigns[:country] || "SE"

        image_id =
          user_id
          |> String.replace(~r/[^\d]/, "")
          |> then(fn s -> if s == "", do: "0", else: s end)
          |> String.to_integer()
          |> rem(2)

        default_avatar_path(country, image_id)
      end

    assigns = assign(assigns, :full_path, full_path)

    ~H"""
    <img class={@class} src={@full_path} loading="lazy" alt="User avatar" />
    """
  end

  defp derive_avatar_assigns(%{user: user} = assigns) when not is_nil(user) do
    assigns
    |> assign(:email, Map.get(user, :email))
    |> assign(:user_id, to_string(Map.get(user, :id, "0")))
    |> assign(:country, Map.get(user, :most_connected_country, "SE"))
    |> assign(
      :avatar_url,
      assigns[:avatar_url] ||
        Ysc.Avatars.resolve_user_avatar_url(user, assigns[:size] || :profile)
    )
  end

  defp derive_avatar_assigns(assigns), do: assigns

  defp default_avatar_path("DK", 0),
    do: ~p"/images/default_avatars/denmark_flag.webp"

  defp default_avatar_path("DK", 1),
    do: ~p"/images/default_avatars/denmark_houses.webp"

  defp default_avatar_path("FI", 0),
    do: ~p"/images/default_avatars/finland_flag.webp"

  defp default_avatar_path("FI", 1),
    do: ~p"/images/default_avatars/finland_house.webp"

  defp default_avatar_path("IS", 0),
    do: ~p"/images/default_avatars/iceland_flag.webp"

  defp default_avatar_path("IS", 1),
    do: ~p"/images/default_avatars/iceland_landscape.webp"

  defp default_avatar_path("NO", 0),
    do: ~p"/images/default_avatars/norway_flag.webp"

  defp default_avatar_path("NO", 1),
    do: ~p"/images/default_avatars/norway_fjord.webp"

  defp default_avatar_path("SE", 0),
    do: ~p"/images/default_avatars/sweden_flag.webp"

  defp default_avatar_path("SE", 1),
    do: ~p"/images/default_avatars/sweden_houses.webp"

  defp default_avatar_path(_, image_id), do: default_avatar_path("SE", image_id)

  attr :color, :string, default: "blue"
  slot :inner_block, required: true

  def alert_box(assigns) do
    ~H"""
    <div
      class={"flex p-4 mb-4 text-sm text-#{@color}-800 rounded bg-#{@color}-50 border border-#{@color}-100"}
      role="alert"
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Centered loading row (spinner + label) for async-loaded sections and modals.

  Uses the standard hero refresh icon with `animate-spin`. Override vertical padding
  via `class` when the default `py-8` is too tight (e.g. modal bodies often use `py-12`).

  ## Examples

      <.async_section_loader :if={@passkeys_loading} id="passkeys-loading" label="Loading passkeys..." />

      <.async_section_loader label="Loading payment methods..." class="py-12" />
  """
  attr :id, :string, default: nil
  attr :label, :string, required: true

  attr :class, :any,
    default: "py-8",
    doc:
      "Tailwind utilities merged with the flex row (default vertical padding is py-8)"

  def async_section_loader(assigns) do
    ~H"""
    <div id={@id} class={["flex items-center justify-center", @class]}>
      <.icon
        name="hero-arrow-path"
        class="w-6 h-6 shrink-0 text-blue-600 animate-spin"
      />
      <span class="ml-3 text-zinc-600 text-sm">{@label}</span>
    </div>
    """
  end

  @doc """
  Compact bordered notice for forms (info or error), used in modals and inline forms.

  For `:info`, a default information icon is shown unless `:icon` is set to another
  hero icon name or `icon={false}` is passed to omit the icon. For `:error`, no icon
  is shown unless `:icon` is set explicitly.

  ## Examples

      <.form_notice kind={:info} id="verify-hint">
        <strong>Keep this window open</strong> while you check your messages.
      </.form_notice>

      <.form_notice :if={@error} kind={:error} id="verify-error">
        {@error}
      </.form_notice>

      <.form_notice kind={:error} margin_bottom={false} id="inline-error">
        Invalid password.
      </.form_notice>
  """
  attr :kind, :atom, values: [:info, :error], required: true
  attr :id, :string, default: nil

  attr :icon, :any,
    default: :default,
    doc: "hero icon name, false to hide, or :default for kind-based default"

  attr :margin_bottom, :boolean, default: true

  slot :inner_block, required: true

  def form_notice(assigns) do
    icon_name = form_notice_icon(assigns.kind, assigns.icon)
    assigns = assign(assigns, :icon_name, icon_name)

    ~H"""
    <div
      id={@id}
      class={[
        "p-3 border rounded-md",
        @kind == :info && "bg-blue-50 border-blue-200",
        @kind == :error && "bg-red-50 border-red-200",
        @margin_bottom && "mb-4"
      ]}
    >
      <p class={[
        "text-sm",
        @kind == :info && "text-blue-800",
        @kind == :error && "text-red-800"
      ]}>
        <.icon
          :if={@icon_name}
          name={@icon_name}
          class="w-5 h-5 inline-block -mt-0.5 me-1"
        />
        {render_slot(@inner_block)}
      </p>
    </div>
    """
  end

  defp form_notice_icon(:info, :default), do: "hero-information-circle"
  defp form_notice_icon(:error, :default), do: nil
  defp form_notice_icon(_kind, false), do: nil
  defp form_notice_icon(_kind, icon) when is_binary(icon), do: icon

  @doc """
  Amber warning panel with leading icon, optional title, and free-form body (often `{raw/1}` HTML).

  Used for booking eligibility and similar server-controlled notices.

  ## Examples

      <.warning_callout title={@booking_error_title}>
        {raw(@booking_disabled_reason)}
      </.warning_callout>
  """
  attr :id, :string, default: nil
  attr :title, :string, default: nil

  attr :class, :any,
    default: nil,
    doc: "Additional classes merged onto the outer container"

  slot :inner_block, required: true

  def warning_callout(assigns) do
    ~H"""
    <div
      id={@id}
      class={["bg-amber-50 border border-amber-200 rounded p-4", @class]}
    >
      <div class="flex items-start">
        <div class="flex-shrink-0">
          <.icon
            name="hero-exclamation-triangle-solid"
            class="h-5 w-5 text-amber-600"
          />
        </div>
        <div class="ms-2 flex-1">
          <h3 :if={@title} class="text-sm font-semibold text-amber-900">
            {@title}
          </h3>
          <div class="mt-2 text-sm text-amber-800">
            <p>{render_slot(@inner_block)}</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :author, :string, required: true
  attr :author_email, :string, required: true
  attr :author_most_connected, :string, required: true
  attr :author_id, :string, required: true
  attr :author_avatar_url, :string, default: nil
  attr :date, :any, required: true
  attr :reply, :boolean, default: false
  attr :form, :any, required: true
  attr :post_id, :string, required: true
  attr :reply_to_comment_id, :string, default: nil
  attr :animate, :boolean, default: false

  def comment(assigns) do
    ~H"""
    <article
      id={@id}
      class={[
        "p-6 bg-zinc-50/50 rounded-xl border border-zinc-100 mb-4 hover:bg-white hover:shadow-xl hover:-translate-y-1 transition-all duration-300",
        @reply && "mb-3 ml-6"
      ]}
      phx-mounted={
        @animate &&
          JS.transition(
            {"transition ease-in duration-500", "opacity-0 ping", "opacity-100"}
          )
      }
    >
      <footer class="flex justify-between items-center mb-4">
        <div class="flex items-center gap-3">
          <.user_avatar_image
            email={@author_email}
            user_id={@author_id}
            country={@author_most_connected}
            avatar_url={@author_avatar_url}
            class="w-8 h-8 rounded-full ring-2 ring-white shadow-sm"
          />
          <div>
            <p class="text-sm font-black text-zinc-900 leading-none">
              {@author}
            </p>
            <p class="text-xs text-zinc-400 font-bold uppercase tracking-widest mt-1">
              <time
                pubdate
                datetime={Timex.format!(@date, "%Y-%m-%d", :strftime)}
                title={Timex.format!(@date, "%B %e, %Y", :strftime)}
              >
                {Timex.format!(@date, "%b %e, %Y", :strftime)}
              </time>
            </p>
          </div>
        </div>
      </footer>
      <p class="text-zinc-600 leading-relaxed ps-11 text-sm md:text-base">
        {@text}
      </p>
      <div :if={!@reply} class="flex items-center mt-4 space-x-4">
        <button
          phx-click={JS.show(to: "#reply-to-#{@id}")}
          type="button"
          class="flex items-center text-sm text-zinc-600 hover:text-zinc-800 hover:bg-zinc-100 rounded font-medium px-2 py-1"
        >
          <.icon
            name="hero-chat-bubble-bottom-center-text"
            class="mr-1.5 w-4 h-4 mt-0.5"
          /> Reply
        </button>
      </div>

      <div :if={!@reply} id={"reply-to-#{@id}"} class="hidden mt-2">
        <.form for={@form} id={"reply-form-#{@post_id}-#{@id}"} phx-submit="save">
          <.input
            field={@form[:text]}
            type="textarea"
            id={"reply-comment-#{@id}"}
            rows="4"
            class="px-0 w-full text-sm text-zinc-900 border-0 focus:ring-0 focus:outline-none"
            placeholder="Write a nice reply..."
            required
          >
          </.input>
          <input type="hidden" name="comment[post_id]" value={@post_id} />
          <input
            type="hidden"
            name="comment[comment_id]"
            value={@reply_to_comment_id}
          />
          <button
            type="submit"
            class="inline-flex items-center py-2.5 px-4 text-sm font-bold text-center text-zinc-100 bg-blue-700 rounded focus:ring-4 focus:ring-blue-200 hover:bg-blue-800 mt-4"
            phx-click={
              JS.dispatch("submit", to: "reply-form-#{@post_id}-#{@id}")
              |> JS.hide(to: "#reply-to-#{@id}")
            }
          >
            Post Reply
          </button>
          <button
            type="button"
            phx-click={JS.hide(to: "#reply-to-#{@id}")}
            class="inline-flex items-center py-2.5 px-4 text-sm font-bold text-center text-zinc-600 rounded focus:ring-4 hover:bg-zinc-100 mt-4"
          >
            Cancel
          </button>
        </.form>
      </div>
    </article>
    """
  end

  attr :id, :string, required: true

  def dummy_component(assigns) do
    ~H"""
    <div
      id={@id}
      class="max-w-0 sm:min-h-0 md:min-h-0 min-h-0 border-1 border-orange-500 hover:border-orange-500 transition-all duration-300"
    >
      <p>Dummy component</p>
    </div>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def toggle_expanded(js \\ %JS{}, id) do
    js
    |> JS.remove_class(
      "expanded",
      to: "##{id}.expanded"
    )
    |> JS.add_class(
      "expanded",
      to: "##{id}:not(.expanded)"
    )
    |> JS.toggle_class("open", to: "##{id}-hamburger")
  end

  def hide_expanded(js \\ %JS{}, id) do
    js
    |> JS.remove_class(
      "expanded",
      to: "##{id}.expanded"
    )
    |> JS.remove_class("open", to: "##{id}-hamburger")
  end

  def close_menu(js \\ %JS{}, id) do
    hide_expanded(js, id)
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition:
        {"transition-all transform ease-out duration-100", "opacity-0",
         "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition:
        {"transition-all transform ease-in duration-50", "opacity-100",
         "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  def show_sidebar(to) do
    JS.remove_class("-translate-x-full", to: to)
    |> JS.add_class("transform-none", to: to)
    |> JS.show(
      to: "#drawer-backdrop",
      transition:
        {"transition-opacity ease-out duration-75", "opacity-0", "opacity-100"}
    )
    |> JS.set_attribute({"aria-expanded", "true"}, to: to)
  end

  def hide_sidebar(to) do
    JS.remove_class("transform-none", to: to)
    |> JS.add_class("-translate-x-full", to: to)
    |> JS.hide(
      to: "#drawer-backdrop",
      transition:
        {"transition-opacity ease-in duration-75", "opacity-100", "opacity-0"}
    )
    |> JS.set_attribute({"aria-expanded", "false"}, to: to)
  end

  def toggle_dropdown(to) do
    # Extract the ID from the selector (e.g., "#about" -> "about")
    id = String.replace(to, "#", "")
    button_id = "##{id}Link"

    # Toggle the dropdown: if it has aria-expanded="true", hide it; otherwise show it
    # Use conditional operations based on the aria-expanded attribute
    JS.toggle_class("hidden", to: to)
    |> JS.toggle_class("dropdown-open", to: button_id)
    # If element will be visible (not hidden), set aria-expanded to true
    |> JS.set_attribute({"aria-expanded", "true"}, to: "#{to}:not(.hidden)")
    # If element will be hidden, remove aria-expanded
    |> JS.remove_attribute("aria-expanded", to: "#{to}.hidden")
    # Apply show/hide transitions conditionally
    |> JS.show(
      to: "#{to}:not(.hidden)",
      transition:
        {"transition ease-out duration-75", "transform opacity-0 scale-95",
         "transform opacity-100 scale-100"}
    )
    |> JS.hide(
      to: "#{to}.hidden",
      transition:
        {"transition ease-in duration-75", "transform opacity-100 scale-100",
         "transform opacity-0 scale-95"}
    )
  end

  def show_dropdown(to) do
    # Extract the ID from the selector (e.g., "#about" -> "about")
    id = String.replace(to, "#", "")

    JS.show(
      to: to,
      transition:
        {"transition ease-out duration-75", "transform opacity-0 scale-95",
         "transform opacity-100 scale-100"}
    )
    |> JS.set_attribute({"aria-expanded", "true"}, to: to)
    |> JS.add_class("dropdown-open", to: "##{id}Link")
  end

  def hide_dropdown(to) do
    # Extract the ID from the selector (e.g., "#about" -> "about")
    id = String.replace(to, "#", "")

    JS.hide(
      to: to,
      transition:
        {"transition ease-in duration-75", "transform opacity-100 scale-100",
         "transform opacity-0 scale-95"}
    )
    |> JS.remove_attribute("aria-expanded", to: to)
    |> JS.remove_class("dropdown-open", to: "##{id}Link")
  end

  @spec translate_error({binary(), keyword() | map()}) :: binary()
  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(YscWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(YscWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  def random_id(prefix) do
    prefix <>
      "_" <> (:crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false))
  end

  @doc """
  Renders a notice banner explaining that membership billing is paused because a
  household member holds a board position.

  Pass `board_member` (the `%User{}` with the board position) and `current_user`
  (the signed-in user) so the copy can be personalised:
  - If `current_user` is the board member themselves, the copy uses "you".
  - Otherwise it names the relevant household member.

  ## Examples

      <.board_pause_notice board_member={@membership_paused_by_board} current_user={@current_user} />

  """
  attr :board_member, :any, required: true
  attr :current_user, :any, required: true

  def board_pause_notice(assigns) do
    ~H"""
    <div
      id="board-pause-notice"
      class="bg-blue-50 border border-blue-200 rounded-md p-4"
    >
      <div class="flex gap-3">
        <.icon
          name="hero-shield-check"
          class="h-5 w-5 text-blue-500 flex-shrink-0 mt-0.5"
        />
        <div class="text-sm text-blue-800 space-y-1">
          <p class="font-semibold">Membership billing paused — board volunteer</p>
          <p>
            <%= if @board_member.id == @current_user.id do %>
              Your membership billing is currently paused while you serve as <span class="font-medium">{Ysc.Accounts.format_board_position(@board_member.board_position)}</span>.
            <% else %>
              Your membership billing is currently paused because
              <span class="font-medium">
                {board_member_display_name(@board_member)}
              </span>
              serves as <span class="font-medium">{Ysc.Accounts.format_board_position(@board_member.board_position)}</span>.
            <% end %>
            Billing will resume automatically 6 months after the board service ends.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp board_member_display_name(%{first_name: first, last_name: last}) do
    case {first, last} do
      {nil, nil} -> "a household member"
      {nil, last} -> last
      {first, nil} -> first
      {first, last} -> "#{first} #{last}"
    end
  end

  @doc """
  Renders a membership status display component.

  ## Examples

      <.membership_status current_membership={@current_membership} />
      <.membership_status current_membership={@current_membership} primary_user={@primary_user} is_sub_account={true} />

  """
  attr :current_membership, :any, required: true
  attr :primary_user, :any, default: nil
  attr :is_sub_account, :boolean, default: false
  attr :scheduled_downgrade_info, :any, default: nil
  attr :class, :string, default: ""

  def membership_status(assigns) do
    ~H"""
    <div
      :if={@current_membership != nil && membership_active?(@current_membership)}
      class={["space-y-4", @class]}
    >
      <div :if={membership_cancelled?(@current_membership)}>
        <div class="bg-yellow-50 border border-yellow-200 rounded-md p-4">
          <p class="text-sm text-yellow-800 font-semibold">
            <.icon
              name="hero-clock"
              class="w-5 h-5 text-yellow-600 inline-block -mt-0.5 me-2"
            />
            <%= if @is_sub_account do %>
              <%= if @primary_user do %>
                The membership from
                <strong>
                  {@primary_user.first_name} {@primary_user.last_name}
                </strong>
                has been canceled.
              <% else %>
                The primary account membership has been canceled.
              <% end %>
            <% else %>
              Your membership has been canceled.
            <% end %>
          </p>

          <p
            :if={get_membership_renewal_date(@current_membership) != nil}
            class="text-sm text-yellow-900 mt-2"
          >
            <%= if @is_sub_account do %>
              You will still have access to membership benefits until <strong>
              <%= format_utc_date_display(get_membership_ends_at(@current_membership)) %>
              </strong>, at which point you will no longer have access to the YSC membership features.
            <% else %>
              You are still an active member until <strong>
              <%= format_utc_date_display(get_membership_ends_at(@current_membership)) %>
              </strong>, at which point you will no longer have access to the YSC membership features.
            <% end %>
          </p>
        </div>
      </div>

      <div :if={
        !membership_cancelled?(@current_membership) &&
          !membership_scheduled_for_cancellation?(@current_membership)
      }>
        <div class="bg-green-50 border border-green-200 rounded-md p-4">
          <p class="text-sm text-green-800 font-semibold">
            <.icon
              name="hero-check-circle"
              class="w-5 h-5 text-green-600 inline-block -mt-0.5 me-2"
            />
            <%= if @is_sub_account do %>
              You have access to an active
              <strong>{get_membership_type(@current_membership)}</strong>
              membership
              <%= if @primary_user do %>
                from
                <strong>
                  {@primary_user.first_name} {@primary_user.last_name}
                </strong>
              <% end %>.
            <% else %>
              You have an active
              <strong>{get_membership_type(@current_membership)}</strong>
              membership.
            <% end %>
          </p>

          <%= if @is_sub_account && @primary_user do %>
            <p class="text-sm text-green-900 mt-2">
              As a family member, you share all membership benefits from the primary account holder.
            </p>
          <% end %>

          <p
            :if={
              get_membership_renewal_date(@current_membership) != nil &&
                !@is_sub_account
            }
            class="text-sm text-green-900 mt-2"
          >
            Auto-renewal is on. Your membership will
            <strong class="text-green-900">automatically renew</strong>
            on
            <strong class="text-green-900">
              {format_utc_date_display(
                get_membership_renewal_date(@current_membership)
              )}
            </strong>
            unless you turn it off beforehand.
          </p>

          <p
            :if={get_membership_type(@current_membership) == "Lifetime"}
            class="text-sm text-green-900 mt-2 font-medium"
          >
            <%= if @is_sub_account do %>
              The lifetime membership never expires and includes all Family membership perks.
            <% else %>
              Your lifetime membership never expires and includes all Family membership perks.
            <% end %>
          </p>
        </div>
      </div>

      <div :if={
        !membership_cancelled?(@current_membership) &&
          membership_scheduled_for_cancellation?(@current_membership) &&
          @scheduled_downgrade_info == nil
      }>
        <div class="bg-yellow-50 border border-yellow-200 rounded-md p-4">
          <p class="text-sm text-yellow-800 font-semibold">
            <.icon
              name="hero-clock"
              class="w-5 h-5 text-yellow-600 inline-block -mt-0.5 me-2"
            />
            <%= if @is_sub_account do %>
              <%= if @primary_user do %>
                The membership from
                <strong>
                  {@primary_user.first_name} {@primary_user.last_name}
                </strong>
                will not automatically renew.
              <% else %>
                The primary account membership will not automatically renew.
              <% end %>
            <% else %>
              Your <strong>{get_membership_type(@current_membership)}</strong>
              membership will not automatically renew.
            <% end %>
          </p>

          <p
            :if={get_membership_renewal_date(@current_membership) != nil}
            class="text-sm text-yellow-900 mt-2"
          >
            <%= if @is_sub_account do %>
              You will still have access to membership benefits until <strong>
              <%= format_utc_date_display(get_membership_renewal_date(@current_membership)) %>
              </strong>. After that date, you will no longer have access to YSC membership features.
            <% else %>
              You are still an active member until <strong>
              <%= format_utc_date_display(get_membership_renewal_date(@current_membership)) %>
              </strong>. After that date, you will no longer have access to YSC membership features.
            <% end %>
          </p>
        </div>
      </div>
    </div>

    <div
      :if={
        @current_membership == nil ||
          (!membership_active?(@current_membership) &&
             !membership_cancelled?(@current_membership))
      }
      class="space-y-4"
    >
      <div class="flex items-center justify-between p-4 bg-red-50 rounded-xl border border-red-200">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <.icon name="hero-exclamation-triangle" class="w-8 h-8 text-red-600" />
          </div>
          <div class="ml-3">
            <h3 class="text-lg font-medium text-red-900">No Active Membership</h3>
            <p class="text-sm text-red-700">
              <%= if @is_sub_account do %>
                <%= if @primary_user do %>
                  The primary account holder (<strong><%= @primary_user.first_name %> <%= @primary_user.last_name %></strong>) does not have an active membership. You need an active membership from the primary account to access YSC events and benefits.
                <% else %>
                  The primary account does not have an active membership. You need an active membership from the primary account to access YSC events and benefits.
                <% end %>
              <% else %>
                You need an active membership to access YSC events and benefits.
              <% end %>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp get_membership_type(membership),
    do: YscWeb.UserAuth.get_membership_type_display_string(membership)

  # Helper functions to handle different membership data structures
  defp membership_active?(%{type: :lifetime}), do: true

  defp membership_active?(%{subscription: subscription})
       when is_map(subscription) do
    Ysc.Subscriptions.active?(subscription)
  end

  defp membership_active?(subscription) when is_struct(subscription) do
    Ysc.Subscriptions.active?(subscription)
  end

  defp membership_active?(_), do: false

  defp membership_cancelled?(%{type: :lifetime}), do: false

  defp membership_cancelled?(%{subscription: subscription})
       when is_map(subscription) do
    Ysc.Subscriptions.cancelled?(subscription)
  end

  defp membership_cancelled?(subscription) when is_struct(subscription) do
    Ysc.Subscriptions.cancelled?(subscription)
  end

  defp membership_cancelled?(_), do: false

  defp membership_scheduled_for_cancellation?(%{type: :lifetime}), do: false

  defp membership_scheduled_for_cancellation?(%{subscription: subscription})
       when is_map(subscription) do
    Ysc.Subscriptions.scheduled_for_cancellation?(subscription)
  end

  defp membership_scheduled_for_cancellation?(subscription)
       when is_struct(subscription) do
    Ysc.Subscriptions.scheduled_for_cancellation?(subscription)
  end

  defp membership_scheduled_for_cancellation?(_), do: false

  defp get_membership_ends_at(%{type: :lifetime}), do: nil

  defp get_membership_ends_at(%{subscription: subscription})
       when is_map(subscription) do
    subscription.ends_at
  end

  defp get_membership_ends_at(subscription) when is_struct(subscription) do
    subscription.ends_at
  end

  defp get_membership_ends_at(_), do: nil

  defp get_membership_renewal_date(%{type: :lifetime}), do: nil

  defp get_membership_renewal_date(%{renewal_date: renewal_date})
       when not is_nil(renewal_date) do
    renewal_date
  end

  defp get_membership_renewal_date(%{subscription: subscription})
       when is_map(subscription) do
    subscription.current_period_end
  end

  defp get_membership_renewal_date(subscription) when is_struct(subscription) do
    subscription.current_period_end
  end

  defp get_membership_renewal_date(_), do: nil

  defp format_utc_date_display(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!("America/Los_Angeles")
    |> DateTime.to_date()
    |> Calendar.strftime("%b %-d, %Y")
  end

  defp format_utc_date_display(%Date{} = date),
    do: Calendar.strftime(date, "%b %-d, %Y")

  defp format_utc_date_display(_), do: ""

  @doc """
  Renders a hero section with a background image or video and optional overlay content.

  The hero is designed to work with a transparent navigation bar. When using this
  component, set `hero_mode: true` in your LiveView assigns to enable transparent
  navigation with white text.

  ## Examples

      <.hero image={~p"/images/hero-bg.jpg"} height="70vh">
        <:title>Welcome to YSC</:title>
        <:subtitle>Your Scandinavian community in the Bay Area</:subtitle>
        <:cta>
          <.link navigate={~p"/events"} class="btn-primary">View Events</.link>
        </:cta>
      </.hero>

      <.hero video={~p"/video/hero.mp4"} height="100vh">
        <:title>Welcome</:title>
      </.hero>

  """
  attr :image, :string, default: nil, doc: "Path to the background image"

  attr :video, :string,
    default: nil,
    doc: "Path to the background video (takes precedence over image)"

  attr :poster, :string,
    default: nil,
    doc: "Path to the poster image shown while video is loading"

  attr :captions, :string,
    default: nil,
    doc:
      "URL to WebVTT captions file (kind=captions). Defaults to shared hero captions when video is set."

  attr :height, :string,
    default: "70vh",
    doc: "Height of the hero section (e.g., '100vh', '500px')"

  attr :overlay, :boolean,
    default: true,
    doc: "Whether to show a dark overlay for text readability"

  attr :overlay_opacity, :string,
    default: "bg-black/40",
    doc: "Tailwind class for overlay opacity"

  attr :class, :string,
    default: nil,
    doc: "Additional classes for the hero container"

  slot :title, doc: "The main hero title"
  slot :subtitle, doc: "Secondary text below the title"
  slot :cta, doc: "Call-to-action buttons or links"
  slot :inner_block, doc: "Additional custom content"

  def hero(assigns) do
    ~H"""
    <section
      id="hero-section"
      phx-hook={@video && "HeroVideoControls"}
      class={[
        "relative w-full flex items-center justify-center overflow-x-hidden overflow-y-auto hero-nav-overlap",
        @video && "group",
        !@video && "bg-cover bg-center bg-no-repeat",
        @class
      ]}
      style={
        if @video,
          do: "min-height: #{@height};",
          else: "background-image: url('#{@image}'); min-height: #{@height};"
      }
    >
      <video
        :if={@video}
        id="hero-video"
        autoplay
        muted
        loop
        playsinline
        poster={@poster}
        class="absolute inset-0 w-full h-full object-cover"
        fetchpriority="high"
      >
        <source src={@video} type="video/mp4" />
        <track
          kind="captions"
          src={@captions || "/video/hero_captions.vtt"}
          srclang="en"
          label="English"
        />
      </video>

      <%!-- Pause/play control: visible on hover (or always on touch) for performance --%>
      <div
        :if={@video}
        class="absolute bottom-4 right-4 z-20 opacity-0 transition-opacity duration-200 group-hover:opacity-100 max-md:opacity-100"
      >
        <button
          type="button"
          data-hero-video-toggle
          aria-label="Pause video"
          class="flex h-12 w-12 items-center justify-center rounded-full bg-white/20 backdrop-blur-sm border border-white/30 text-white shadow-lg hover:bg-white/30 hover:border-white/50 transition-colors focus:outline-none focus:ring-2 focus:ring-white/50 focus:ring-offset-2 focus:ring-offset-transparent"
        >
          <span class="pause-icon inline-flex [.paused_&]:hidden">
            <.icon name="hero-pause" class="w-6 h-6" />
          </span>
          <span class="play-icon hidden [.paused_&]:!inline-flex">
            <.icon name="hero-play" class="w-6 h-6" />
          </span>
        </button>
      </div>

      <div
        :if={@overlay}
        class={["absolute inset-0 z-[1]", @overlay_opacity]}
        aria-hidden="true"
      />

      <div class="relative z-10 w-full min-w-0 max-w-screen-lg mx-auto px-5 sm:px-6 py-12 sm:py-14 md:py-16 text-center text-white box-border flex flex-col items-center justify-center">
        <h1
          :if={@title != []}
          class="text-4xl md:text-5xl lg:text-6xl font-bold tracking-tight drop-shadow-lg"
        >
          {render_slot(@title)}
        </h1>

        <p
          :if={@subtitle != []}
          class="mt-6 text-lg md:text-xl lg:text-2xl max-w-2xl mx-auto drop-shadow-md"
        >
          {render_slot(@subtitle)}
        </p>

        <div :if={@cta != []} class="mt-8 flex flex-wrap gap-4 justify-center">
          {render_slot(@cta)}
        </div>

        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  @doc """
  Renders an official "Add to Apple Wallet" badge linking to the given href.

  Uses Apple's provided SVG artwork as required by the
  Add to Apple Wallet badge guidelines.

  ## Examples

      <.add_to_wallet_button href="/wallet/tickets/abc123" />
  """
  attr :href, :string, required: true

  def add_to_wallet_button(assigns) do
    ~H"""
    <a href={@href}>
      <img
        src={~p"/images/apple/US-UK_Add_to_Apple_Wallet_RGB_101421.svg"}
        alt="Add to Apple Wallet"
        class="block w-[200px]"
      />
    </a>
    """
  end

  @doc """
  Renders an official "Add to Google Wallet" badge linking to the given href.

  Uses Google's provided SVG artwork as required by the
  Add to Google Wallet badge guidelines. Opens in a new tab since the save URL
  navigates to Google's domain.

  ## Examples

      <.add_to_google_wallet_button href="https://pay.google.com/gp/v/save/..." />
  """
  attr :href, :string, required: true

  def add_to_google_wallet_button(assigns) do
    ~H"""
    <a href={@href} target="_blank" rel="noopener noreferrer">
      <img
        src={~p"/images/google/enGB_add_to_google_wallet_add-wallet-badge.svg"}
        alt="Add to Google Wallet"
        class="block w-[200px]"
      />
    </a>
    """
  end

  @doc """
  Renders a QR code as an inline SVG.

  ## Examples

      <.qr_code data="https://example.com" />
      <.qr_code data={@token} size={200} class="mx-auto" />
  """
  attr :data, :string, required: true
  attr :size, :integer, default: 250
  attr :class, :string, default: ""

  def qr_code(assigns) do
    svg =
      assigns.data
      |> EQRCode.encode()
      |> EQRCode.svg(width: assigns.size)

    assigns = assign(assigns, :svg, svg)

    ~H"""
    <div class={["inline-block", @class]}>
      {Phoenix.HTML.raw(@svg)}
    </div>
    """
  end

  @doc """
  Renders a skeleton placeholder while the Stripe Payment Element loads.

  Mimics the layout of card tabs and input fields with a shimmer animation.

  ## Examples

      <.payment_element_loading />
      <.payment_element_loading id="custom-loading-id" class="mt-4" />
  """
  attr :id, :string, default: "payment-element-loading"
  attr :class, :string, default: ""

  def payment_element_loading(assigns) do
    ~H"""
    <div
      id={@id}
      aria-busy="true"
      aria-label="Loading secure payment form"
      class={[
        "mb-6 min-h-[12rem] rounded-lg border border-zinc-200 bg-white p-4 space-y-4",
        @class
      ]}
    >
      <div class="flex gap-2">
        <div class="skeleton-shimmer h-10 flex-1 rounded-md bg-zinc-100" />
        <div class="skeleton-shimmer h-10 flex-1 rounded-md bg-zinc-50 opacity-70" />
      </div>

      <div class="space-y-2">
        <div class="skeleton-shimmer h-3 w-24 rounded bg-zinc-100" />
        <div class="skeleton-shimmer h-11 w-full rounded-md bg-zinc-100" />
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div class="space-y-2">
          <div class="skeleton-shimmer h-3 w-16 rounded bg-zinc-100" />
          <div class="skeleton-shimmer h-11 w-full rounded-md bg-zinc-100" />
        </div>
        <div class="space-y-2">
          <div class="skeleton-shimmer h-3 w-10 rounded bg-zinc-100" />
          <div class="skeleton-shimmer h-11 w-full rounded-md bg-zinc-100" />
        </div>
      </div>

      <p class="flex items-center gap-1.5 pt-1 text-xs text-zinc-400">
        <.icon name="hero-lock-closed" class="w-3 h-3" />
        Loading secure payment form…
      </p>
    </div>
    """
  end
end
