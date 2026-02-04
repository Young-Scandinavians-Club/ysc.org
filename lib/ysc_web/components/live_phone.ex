defmodule LivePhone do
  @moduledoc """
  LiveView component for phone number input with country selection.

  Provides an interactive phone number input field with country code selection
  and validation.
  """
  use Phoenix.LiveComponent
  import Phoenix.HTML.Form
  use PhoenixHTMLHelpers

  alias Phoenix.LiveView.Socket
  alias LivePhone.{Country, Util}

  @impl true
  @spec mount(map()) :: {:ok, map()}
  def mount(socket) do
    {:ok,
     socket
     |> assign_new(:preferred, fn -> ["US", "GB"] end)
     |> assign_new(:tabindex, fn -> 0 end)
     |> assign_new(:apply_format?, fn -> false end)
     |> assign_new(:value, fn -> "" end)
     |> assign_new(:opened?, fn -> false end)
     |> assign_new(:valid?, fn -> false end)}
  end

  @impl true
  def update(assigns, socket) do
    current_country =
      assigns[:country] || socket.assigns[:country] ||
        hd(assigns[:preferred] || ["US"])

    masks =
      if assigns[:apply_format?] do
        current_country
        |> get_masks()
        |> Enum.join(",")
      end

    socket =
      socket
      |> assign(assigns)
      |> assign_country(current_country)
      |> assign(:masks, masks)

    {:ok, set_value(socket, socket.assigns.value)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class={"live_phone relative flex rounded bg-white border-1 mt-2 border-zinc-300 #{if @valid?, do: "live_phone-valid"}"}
      id={"live_phone-#{@id}"}
      phx-hook="LivePhone"
    >
      <.country_selector
        tabindex={@tabindex}
        target={@myself}
        opened?={@opened?}
        country={@country}
        wrapper={"live_phone-#{@id}"}
      />

      <input
        type="tel"
        class={[
          "live_phone-input text-zinc-900 border-1 rounded-r w-full focus:ring-0 sm:text-sm sm:leading-6 bg-none flex-1",
          @class
        ]}
        value={assigns[:value]}
        tabindex={assigns[:tabindex]}
        placeholder={assigns[:placeholder] || get_placeholder(assigns[:country])}
        data-masks={@masks}
        phx-target={@myself}
        phx-keyup="typing"
        phx-debounce="300"
        phx-blur="blur"
      />
      <input type="hidden" name={@name} value={assigns[:formatted_value]} />

      <%= if @opened? do %>
        <.country_list
          country={@country}
          preferred={@preferred}
          id={@id}
          target={@myself}
        />
      <% end %>
    </div>
    """
  end

  defguardp is_empty(value) when is_nil(value) or value == ""

  @spec set_value(Socket.t(), String.t()) :: Socket.t()
  def set_value(socket, value) do
    value =
      case value do
        empty when is_empty(empty) ->
          case socket.assigns do
            %{form: form, field: field}
            when not is_nil(form) and not is_nil(field) ->
              input_value(form, field)

            %{value: assigns_value} when not is_nil(assigns_value) ->
              value

            _ ->
              value
          end

        found_value ->
          found_value
      end || ""

    {_, formatted_value} = Util.normalize(value, socket.assigns[:country])
    value = apply_mask(value, socket.assigns[:country])
    valid? = Util.valid?(formatted_value)

    push? = socket.assigns[:formatted_value] != formatted_value

    socket
    |> assign(:valid?, valid?)
    |> assign(:value, value)
    |> assign(:formatted_value, formatted_value)
    |> then(fn socket ->
      if push? do
        push_event(socket, "change", %{
          id: "live_phone-#{socket.assigns.id}",
          value: formatted_value
        })
      else
        socket
      end
    end)
  end

  defp apply_mask(value, _country) when is_empty(value), do: value

  defp apply_mask(value, country) do
    case ExPhoneNumber.parse(value, country) do
      {:ok, phone_number} ->
        metadata = ExPhoneNumber.Metadata.get_for_region_code(country)

        national_significant_number =
          ExPhoneNumber.Model.PhoneNumber.get_national_significant_number(
            phone_number
          )

        ExPhoneNumber.Formatting.format_nsn(
          national_significant_number,
          metadata,
          :international
        )

      _ ->
        ""
    end
  end

  @impl true
  def handle_event("typing", %{"value" => value}, socket) do
    {:noreply, set_value(socket, value)}
  end

  def handle_event("blur", %{"value" => value}, socket) do
    socket = set_value(socket, value)

    # Force validation on blur by pushing change event immediately
    {:noreply,
     socket
     |> assign(:opened?, false)
     |> push_event("change", %{
       id: "live_phone-#{socket.assigns.id}",
       value: socket.assigns[:formatted_value]
     })}
  end

  def handle_event("select_country", %{"country" => country}, socket) do
    valid? = Util.valid?(socket.assigns[:formatted_value])

    placeholder =
      if socket.assigns[:country] == country do
        socket.assigns[:placeholder]
      else
        get_placeholder(country)
      end

    {:noreply,
     socket
     |> assign_country(country)
     |> assign(:valid?, valid?)
     |> assign(:opened?, false)
     |> assign(:placeholder, placeholder)
     |> push_event("focus", %{id: "live_phone-#{socket.assigns.id}"})}
  end

  def handle_event("toggle", _, socket) do
    {:noreply, assign(socket, :opened?, socket.assigns.opened? != true)}
  end

  def handle_event("close", _, socket) do
    close_dropdown(socket)
  end

  defp close_dropdown(socket) do
    {:noreply, assign(socket, :opened?, false)}
  end

  @spec get_placeholder(String.t()) :: String.t()
  defp get_placeholder(country) do
    country
    |> ExPhoneNumber.Metadata.get_for_region_code()
    |> case do
      %{country_code: country_code, fixed_line: %{example_number: number}} ->
        number
        |> String.replace(~r/\d/, "5")
        |> ExPhoneNumber.parse(country)
        |> case do
          {:ok, result} ->
            result
            |> ExPhoneNumber.format(:international)
            |> String.replace(~r/^(\+|00)#{country_code}/, "")
            |> String.trim()

          _ ->
            ""
        end
    end
  end

  @spec get_masks(String.t()) :: [String.t()]
  defp get_masks(country) do
    metadata = ExPhoneNumber.Metadata.get_for_region_code(country)

    # Iterate through all metadata to find phone number descriptions
    # with example numbers only, and return those example numbers
    metadata
    |> Map.from_struct()
    |> Enum.map(fn
      {_, %ExPhoneNumber.Metadata.PhoneNumberDescription{} = desc} ->
        desc.example_number

      _other ->
        nil
    end)
    |> Enum.filter(& &1)

    # Parse all example numbers with the country and only keep valid ones
    |> Enum.map(&ExPhoneNumber.parse(&1, country))
    |> Enum.map(fn
      {:ok, parsed} -> parsed
      _other -> nil
    end)
    |> Enum.filter(& &1)

    # Format all parsed numbers with the international format
    # but removing the leading country_code. Transform all digits to X
    # to be used for a mask
    |> Enum.map(&ExPhoneNumber.format(&1, :international))
    |> Enum.map(&String.replace(&1, ~r/^(\+|00)#{metadata.country_code}/, ""))
    |> Enum.map(&String.replace(&1, ~r/\d/, "X"))
    |> Enum.map(&String.trim/1)

    # And make sure we only have unique ones
    |> Enum.uniq()
  end

  @spec assign_country(Socket.t(), Country.t() | String.t()) :: Socket.t()
  defp assign_country(socket, %Country{code: country}),
    do: assign_country(socket, country)

  defp assign_country(socket, country), do: assign(socket, :country, country)

  defp country_selector(assigns) do
    region_code =
      case ExPhoneNumber.Metadata.get_for_region_code(assigns[:country]) do
        nil -> ""
        code -> "+#{code.country_code}"
      end

    assigns = assign(assigns, :region_code, region_code)

    ~H"""
    <div
      class={"live_phone-country align-middle text-center hover:bg-zinc-100 transition duration-150 ease-in-out justify-center cursor-pointer flex px-3 py-2 rounded-l border-1 border-l border-t border-b border-zinc-300 #{if @opened?, do: "border-zinc-400 bg-zinc-100"}"}
      tabindex={@tabindex}
      phx-target={@target}
      phx-click="toggle"
      aria-owns={@wrapper}
      aria-expanded={to_string(@opened?)}
      role="combobox"
    >
      <span class={"live_phone-country-flag rounded w-7 h-6 fi fi-" <> String.downcase(@country)} />
      <span class="live_phone-country-code text-sm text-zinc-600 px-3 mt-0.5">
        <%= @region_code %>
      </span>
      <span class={"w-4 text-zinc-600 mt-1 #{if @opened?, do: "hero-chevron-up", else: "hero-chevron-down"}"} />
    </div>
    """
  end

  defp country_list(assigns) do
    assigns =
      if assigns[:country] do
        assign(assigns, :preferred, [assigns[:country] | assigns[:preferred]])
      else
        assigns
      end

    assigns =
      assign_new(assigns, :countries, fn ->
        Country.list(assigns[:preferred])
      end)

    assigns =
      assign_new(assigns, :last_preferred, fn ->
        assigns[:countries]
        |> Enum.filter(& &1.preferred)
        |> List.last()
      end)

    ~H"""
    <ul
      class="live_phone-country-list overflow-auto absolute text-left list-none top-full w-72 max-h-80 bg-white rounded shadow px-2 m-0 z-10"
      id={"live_phone-country-list-#{@id}"}
      role="listbox"
    >
      <%= for country <- @countries do %>
        <.country_list_item
          country={country}
          current_country={@country}
          target={@target}
        />

        <%= if country == @last_preferred do %>
          <li
            aria-disabled="true"
            class="live_phone-country-separator m-0 height-0 p-0 overflow-hidden border-b border-1 border-zinc-200"
            role="separator"
          >
          </li>
        <% end %>
      <% end %>
    </ul>
    """
  end

  defp country_list_item(assigns) do
    selected? = assigns[:country].code == assigns[:current_country]
    assigns = assign(assigns, :selected?, selected?)

    class = [
      "live_phone-country-item flex text-sm cursor-pointer m-0 px-1 py-1 hover:bg-white"
    ]

    class = if assigns[:selected?], do: ["bg-white" | class], else: class

    class =
      if assigns[:country].preferred, do: ["preferred" | class], else: class

    assigns = assign(assigns, :class, class)

    ~H"""
    <li
      aria-selected={to_string(@selected?)}
      class={@class}
      phx-click="select_country"
      phx-target={@target}
      phx-value-country={@country.code}
      role="option"
    >
      <span class={"live_phone-country-item-flag rounded-full w-6 h-6 fi fi-" <>  String.downcase(@country.code)}>
      </span>
      <span class="live_phone-country-item-name text-zinc-600 inline-block text-sm px-2 whitespace-nowrap text-ellipsis overflow-hidden">
        <%= @country.name %>
      </span>
      <span class="live_phone-country-code text-sm text-zinc-400">
        +<%= @country.region_code %>
      </span>
    </li>
    """
  end
end
