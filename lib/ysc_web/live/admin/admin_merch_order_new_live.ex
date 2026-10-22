defmodule YscWeb.AdminMerchOrderNewLive do
  @moduledoc """
  Place a club-paid ("free") merch order: for a member, for the admin
  themselves, or to a custom address (event giveaways, sponsors).

  Two steps. First the details (recipient, items, why), then a review that
  shows Printful's shipping options and what the order will cost the club
  before anything is sent. Placing the order sends it to Printful and emails
  the board a summary naming who placed it.

  The first HTML is a skeleton. Product and event queries run after the
  WebSocket connects so the HTTP response is never blocked on those loads,
  and they run once instead of on both the disconnected and connected mounts.
  """
  use YscWeb, :admin_live_view

  on_mount {YscWeb.UserAuth, :ensure_full_admin}

  import YscWeb.ShopComponents, only: [shipping_address_lines: 1]

  alias Ysc.Merch.{AdminOrders, ShippingAddress}
  alias Ysc.Repo
  alias YscWeb.Admin.DateTimeDisplay
  alias YscWeb.AdminUserSearch

  @address_fields ~w(name address1 address2 city state_code zip phone email)
  @recipient_kinds [
    {"member", "A member"},
    {"self", "Me"},
    {"custom", "Someone else"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:active_page, :merch)
      |> assign(:page_title, "New club-paid order")
      |> assign(:step, :details)
      |> assign(:products, [])
      |> assign(:variant_options, [])
      |> assign(:event_options, [])
      |> assign(:form_options_loaded, false)
      |> assign(:errors, %{})
      |> assign(:lines_error, nil)
      |> assign(:recipient_error, nil)
      |> assign(:attempted?, false)
      |> assign(:summary, [])
      |> assign(:review, nil)
      |> assign(:review_error, nil)
      |> assign(:placing?, false)
      |> assign(:address, nil)
      |> assign(:order_lines, [])
      |> AdminUserSearch.assign_blank()
      |> assign_form(default_params())

    {:ok,
     if connected?(socket) do
       load_form_options(socket)
     else
       socket
     end}
  end

  defp load_form_options(socket) do
    products = AdminOrders.orderable_products()

    socket
    |> assign(:products, products)
    |> assign(:variant_options, variant_options(products))
    |> assign(:event_options, event_options(AdminOrders.linkable_events()))
    |> assign(:form_options_loaded, true)
  end

  defp default_params do
    blank = Map.new(@address_fields, &{&1, ""})

    Map.merge(blank, %{
      "recipient" => "member",
      "purpose" => "",
      "event_id" => "",
      "lines" => %{"0" => %{"variant_id" => "", "quantity" => "1"}}
    })
  end

  defp assign_form(socket, params) do
    errors =
      for {field, messages} <- socket.assigns[:errors] || %{},
          message <- Enum.take(messages, 1),
          do: {field, {message, []}}

    socket
    |> assign(:params, params)
    |> assign(:form, to_form(params, as: :order, errors: errors))
  end

  ## Events

  @impl true
  def handle_event("validate", %{"order" => submitted}, socket) do
    previous = socket.assigns.params
    params = merge_params(previous, submitted)

    socket =
      if params["recipient"] != previous["recipient"],
        do: switch_recipient(socket, params),
        else: assign_form(socket, params)

    {:noreply, refresh_problems(socket)}
  end

  def handle_event("search-users", %{"value" => query}, socket) do
    {:noreply, AdminUserSearch.search(socket, query)}
  end

  def handle_event("select-user", %{"id" => id}, socket) do
    socket = AdminUserSearch.select(socket, id)

    user =
      Repo.preload(socket.assigns.selected_user, :billing_address)

    {:noreply,
     socket
     |> assign(:recipient_error, nil)
     |> assign_form(put_address(socket.assigns.params, user))
     |> refresh_problems()}
  end

  def handle_event("clear-user", _params, socket) do
    {:noreply,
     socket
     |> AdminUserSearch.assign_blank()
     |> assign_form(clear_address(socket.assigns.params))
     |> refresh_problems()}
  end

  def handle_event("add_line", _params, socket) do
    lines = socket.assigns.params["lines"]
    next = lines |> Map.keys() |> Enum.map(&String.to_integer/1) |> Enum.max()

    lines =
      Map.put(lines, to_string(next + 1), %{
        "variant_id" => "",
        "quantity" => "1"
      })

    {:noreply,
     assign_form(socket, Map.put(socket.assigns.params, "lines", lines))}
  end

  def handle_event("remove_line", %{"key" => key}, socket) do
    lines = Map.delete(socket.assigns.params["lines"], key)

    if map_size(lines) == 0 do
      {:noreply, socket}
    else
      {:noreply,
       assign_form(socket, Map.put(socket.assigns.params, "lines", lines))}
    end
  end

  def handle_event("review", %{"order" => submitted}, socket) do
    params = merge_params(socket.assigns.params, submitted)

    case validate_details(params, socket.assigns.selected_user) do
      {:ok, address, lines} ->
        {:noreply,
         socket
         |> clear_problems()
         |> assign_form(params)
         |> assign(:address, address)
         |> assign(:order_lines, lines)
         |> assign(:step, :review)
         |> assign(:review, :loading)
         |> assign(:review_error, nil)
         |> start_review(address, lines)}

      {:error, problems} ->
        {:noreply,
         socket
         |> assign(:attempted?, true)
         |> show_problems(problems)
         |> assign_form(params)}
    end
  end

  def handle_event("back", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :details)
     |> assign(:review, nil)
     |> assign(:review_error, nil)}
  end

  def handle_event("retry_review", _params, socket) do
    {:noreply,
     socket
     |> assign(:review, :loading)
     |> assign(:review_error, nil)
     |> start_review(socket.assigns.address, socket.assigns.order_lines)}
  end

  def handle_event(
        "select_option",
        %{"shipping" => option_id},
        %{assigns: %{review: %{options: options} = review}} = socket
      ) do
    case Enum.find(options, &(&1.id == option_id)) do
      nil ->
        {:noreply, socket}

      option ->
        address = socket.assigns.address
        lines = socket.assigns.order_lines

        {:noreply,
         socket
         |> assign(:review, %{review | option: option, estimate: :loading})
         |> start_async(:estimate, fn ->
           AdminOrders.estimate_cost(address, lines, option.id)
         end)}
    end
  end

  def handle_event("select_option", _params, socket), do: {:noreply, socket}

  def handle_event(
        "place_order",
        _params,
        %{assigns: %{placing?: true}} = socket
      ),
      do: {:noreply, socket}

  def handle_event(
        "place_order",
        _params,
        %{assigns: %{review: %{option: option, estimate: estimate}}} = socket
      )
      when is_map(option) do
    params = socket.assigns.params

    case AdminOrders.create_comp_order(placing_admin(socket), %{
           address: socket.assigns.address,
           lines: socket.assigns.order_lines,
           option: option,
           purpose: String.trim(params["purpose"]),
           user_id: recipient_user_id(params, socket),
           event_id: blank_to_nil(params["event_id"]),
           estimated_cost: estimated_cost(estimate)
         }) do
      {:ok, order} ->
        {:noreply,
         socket
         |> assign(:placing?, true)
         |> YscWeb.Flash.put_toast(
           :info,
           "Order #{order.reference_id} is on its way to Printful. The board has been emailed a summary.",
           title: "Order placed"
         )
         |> push_navigate(to: ~p"/admin/merch/orders/#{order.id}")}

      {:error, reason} ->
        {:noreply,
         YscWeb.Flash.put_toast(socket, :error, place_error(reason),
           title: "Order not placed"
         )}
    end
  end

  def handle_event("place_order", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:review, {:ok, {:ok, review}}, socket) do
    {:noreply, assign(socket, :review, review)}
  end

  def handle_async(:review, {:ok, {:error, {:rejected, message}}}, socket) do
    {:noreply,
     socket
     |> assign(:step, :details)
     |> assign(:review, nil)
     |> YscWeb.Flash.put_toast(
       :error,
       "Printful can't ship this: #{message}",
       title: "Check the address and items"
     )}
  end

  def handle_async(:review, {:ok, {:error, _}}, socket) do
    {:noreply,
     socket
     |> assign(:review, nil)
     |> assign(
       :review_error,
       "Printful couldn't quote shipping just now. Try again in a moment."
     )}
  end

  def handle_async(:review, {:exit, _reason}, socket) do
    handle_async(:review, {:ok, {:error, :unavailable}}, socket)
  end

  def handle_async(
        :estimate,
        {:ok, result},
        %{assigns: %{review: %{} = review}} = socket
      ) do
    estimate = if match?({:ok, _}, result), do: result, else: :unavailable
    {:noreply, assign(socket, :review, %{review | estimate: estimate})}
  end

  def handle_async(
        :estimate,
        _other,
        %{assigns: %{review: %{} = review}} = socket
      ) do
    {:noreply, assign(socket, :review, %{review | estimate: :unavailable})}
  end

  def handle_async(:estimate, _other, socket), do: {:noreply, socket}

  defp start_review(socket, address, lines) do
    start_async(socket, :review, fn -> AdminOrders.review(address, lines) end)
  end

  ## Params

  # The form posts every field on each change, but `lines` is a nested map
  # and the member picker lives outside it, so merge instead of replacing.
  defp merge_params(previous, submitted) do
    submitted = drop_unused_markers(submitted)

    previous
    |> Map.merge(Map.drop(submitted, ["lines"]))
    |> Map.put("lines", Map.get(submitted, "lines", previous["lines"]))
  end

  # LiveView flags fields the user has not touched with `_unused_*` keys, and
  # Phoenix hides the errors of "unused" fields. Everything on this form is
  # checked together when the admin presses Review, so none of them count.
  defp drop_unused_markers(params) when is_map(params) do
    params
    |> Enum.reject(fn {key, _} -> String.starts_with?(key, "_unused_") end)
    |> Map.new(fn {key, value} -> {key, drop_unused_markers(value)} end)
  end

  defp drop_unused_markers(value), do: value

  ## Problems

  defp show_problems(socket, problems) do
    socket
    |> assign(:errors, problems.fields)
    |> assign(:lines_error, problems.lines)
    |> assign(:recipient_error, problems.recipient)
    |> assign(:summary, summarize(problems))
  end

  defp clear_problems(socket) do
    socket
    |> assign(:attempted?, false)
    |> assign(:errors, %{})
    |> assign(:lines_error, nil)
    |> assign(:recipient_error, nil)
    |> assign(:summary, [])
  end

  # Once Review has been pressed, keep the problems current as the admin
  # fixes them, so a fixed field stops being flagged straight away.
  defp refresh_problems(%{assigns: %{attempted?: true}} = socket) do
    socket =
      case validate_details(
             socket.assigns.params,
             socket.assigns.selected_user
           ) do
        {:ok, _address, _lines} -> clear_problems(socket)
        {:error, problems} -> show_problems(socket, problems)
      end

    assign_form(socket, socket.assigns.params)
  end

  defp refresh_problems(socket), do: socket

  @field_labels %{
    name: "Name",
    address1: "Address",
    address2: "Apartment",
    city: "City",
    state_code: "State",
    zip: "ZIP code",
    phone: "Phone",
    email: "Email"
  }

  # One line per problem, for the box next to the Review button (the fields
  # themselves can be far above it).
  defp summarize(problems) do
    address =
      for field <- Enum.map(@address_fields, &String.to_existing_atom/1),
          message <- Enum.take(Map.get(problems.fields, field, []), 1),
          do: "#{Map.fetch!(@field_labels, field)} #{message}"

    purpose = Map.get(problems.fields, :purpose, [])

    ([problems.recipient | address] ++ [problems.lines | purpose])
    |> Enum.reject(&is_nil/1)
  end

  defp switch_recipient(socket, params) do
    case params["recipient"] do
      "self" ->
        admin = placing_admin(socket) |> Repo.preload(:billing_address)

        socket
        |> AdminUserSearch.assign_blank()
        |> assign(:recipient_error, nil)
        |> assign_form(put_address(params, admin))

      "member" ->
        socket
        |> AdminUserSearch.assign_blank()
        |> assign_form(clear_address(params))

      _custom ->
        socket
        |> AdminUserSearch.assign_blank()
        |> assign(:recipient_error, nil)
        |> assign_form(clear_address(params))
    end
  end

  defp put_address(params, user) do
    address = ShippingAddress.from_user(user)

    Enum.reduce(@address_fields, params, fn field, acc ->
      Map.put(
        acc,
        field,
        Map.get(address, String.to_existing_atom(field)) || ""
      )
    end)
  end

  defp clear_address(params),
    do: Enum.reduce(@address_fields, params, &Map.put(&2, &1, ""))

  defp validate_details(params, selected_user) do
    address_result = ShippingAddress.validate(Map.take(params, @address_fields))
    lines_result = AdminOrders.resolve_lines(selections(params["lines"]))
    purpose = String.trim(params["purpose"] || "")

    recipient_error =
      if params["recipient"] == "member" and is_nil(selected_user),
        do: "Choose the member this is for."

    fields =
      %{}
      |> put_address_errors(address_result)
      |> then(fn errors ->
        if purpose == "",
          do:
            Map.put(errors, :purpose, ["Say why the club is paying for this"]),
          else: errors
      end)

    lines_error =
      case lines_result do
        {:ok, _} ->
          nil

        {:error, :no_items} ->
          "Add at least one item."

        {:error, :invalid_quantity} ->
          "Quantities must be between 1 and 500."

        {:error, :unavailable_variant} ->
          "One of those items is no longer available."
      end

    with {:ok, address} <- address_result,
         {:ok, lines} <- lines_result,
         true <- fields == %{} and is_nil(recipient_error) do
      {:ok, address, lines}
    else
      _ ->
        {:error,
         %{fields: fields, lines: lines_error, recipient: recipient_error}}
    end
  end

  defp put_address_errors(errors, {:ok, _}), do: errors

  defp put_address_errors(errors, {:error, changeset}) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.reduce(errors, fn {field, messages}, acc ->
      Map.put(acc, field, messages)
    end)
  end

  defp selections(lines) when is_map(lines) do
    lines
    |> Enum.sort_by(fn {key, _} -> String.to_integer(key) end)
    |> Enum.map(fn {_key, line} ->
      %{
        variant_id: blank_to_nil(line["variant_id"]),
        quantity: parse_quantity(line["quantity"])
      }
    end)
  end

  defp parse_quantity(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp recipient_user_id(%{"recipient" => "self"}, socket),
    do: placing_admin(socket).id

  defp recipient_user_id(%{"recipient" => "member"}, socket),
    do: socket.assigns.selected_user && socket.assigns.selected_user.id

  defp recipient_user_id(_custom, _socket), do: nil

  # The real admin, not whoever they might be impersonating.
  defp placing_admin(socket),
    do: socket.assigns[:real_current_user] || socket.assigns.current_user

  defp estimated_cost({:ok, %{total: total}}), do: total
  defp estimated_cost(_), do: nil

  defp place_error(:no_items), do: "Add at least one item."

  defp place_error(:not_authorized),
    do: "Only full admins can place these orders."

  defp place_error(%Ecto.Changeset{}), do: "Check the details and try again."

  defp place_error(_),
    do: "Something went wrong placing the order. Nothing was sent."

  ## View helpers

  defp variant_options(products) do
    for {product, variants} <- products do
      {product.name, for(v <- variants, do: {v.name, v.id})}
    end
  end

  defp event_options(events) do
    [{"No event", ""}] ++
      for e <- events do
        label =
          if e.start_date,
            do:
              "#{e.title} (#{DateTimeDisplay.format_event_date(e.start_date)})",
            else: e.title

        {label, e.id}
      end
  end

  defp line_keys(params) do
    params["lines"]
    |> Map.keys()
    |> Enum.sort_by(&String.to_integer/1)
  end

  defp recipient_kinds, do: @recipient_kinds

  defp event_title(params, options) do
    case Enum.find(options, fn {_label, id} -> id == params["event_id"] end) do
      {label, id} when id != "" -> label
      _ -> nil
    end
  end

  defp shipping_options(options),
    do: Enum.map(options, &{shipping_label(&1), &1.id})

  # Printful's option names already carry the delivery window.
  defp shipping_label(option),
    do: "#{option.name} · #{Money.to_string!(option.rate)}"

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <.admin_page_header subtitle="The club pays. Printful bills the club's card; nobody is charged.">
        New club-paid order
      </.admin_page_header>

      <div class="w-full max-w-3xl pb-16 pt-4">
        <.admin_table_skeleton
          :if={!@form_options_loaded}
          id="admin-merch-order-new-loading"
          rows={8}
          columns={2}
        />

        <.details_step
          :if={@step == :details and @form_options_loaded}
          form={@form}
          params={@params}
          errors={@errors}
          lines_error={@lines_error}
          recipient_error={@recipient_error}
          summary={@summary}
          variant_options={@variant_options}
          event_options={@event_options}
          selected_user={@selected_user}
          user_search={@user_search}
          user_search_results={@user_search_results}
        />

        <.review_step
          :if={@step == :review}
          params={@params}
          address={@address}
          lines={@order_lines}
          review={@review}
          review_error={@review_error}
          event_options={@event_options}
          placing?={@placing?}
        />
      </div>
    </.side_menu>
    """
  end

  attr :form, :any, required: true
  attr :params, :map, required: true
  attr :errors, :map, required: true
  attr :lines_error, :string, default: nil
  attr :recipient_error, :string, default: nil
  attr :summary, :list, default: []
  attr :variant_options, :list, required: true
  attr :event_options, :list, required: true
  attr :selected_user, :any, default: nil
  attr :user_search, :string, default: ""
  attr :user_search_results, :list, default: []

  defp details_step(assigns) do
    ~H"""
    <.form
      for={@form}
      id="merch-order-form"
      phx-change="validate"
      phx-submit="review"
      class="space-y-10"
    >
      <section id="order-recipient" class="space-y-5">
        <h2 class="text-lg text-zinc-800 type-subhead">Who is it for?</h2>

        <fieldset class="flex flex-wrap gap-x-6 gap-y-2">
          <legend class="sr-only">Recipient</legend>
          <label
            :for={{value, label} <- recipient_kinds()}
            class="inline-flex min-h-11 cursor-pointer items-center gap-2 text-sm text-zinc-800"
          >
            <input
              type="radio"
              name="order[recipient]"
              id={"recipient-#{value}"}
              value={value}
              checked={@params["recipient"] == value}
              class="size-4 border-zinc-300 text-blue-600 focus:ring-blue-600"
            />
            {label}
          </label>
        </fieldset>

        <div :if={@params["recipient"] == "member"}>
          <.admin_user_autocomplete
            id="merch-order-member"
            label="Member"
            name="order[user_id]"
            search_event="search-users"
            select_event="select-user"
            clear_event="clear-user"
            search_value={@user_search}
            results={@user_search_results}
            selected={@selected_user}
            errors={List.wrap(@recipient_error)}
            required
          />
        </div>

        <div
          :if={@params["recipient"] != "member" or @selected_user}
          id="order-address"
          class="grid grid-cols-1 gap-4 sm:grid-cols-6"
        >
          <p class="text-sm text-zinc-500 sm:col-span-6">
            We ship within the United States. Check the address; it is what Printful will use.
          </p>
          <div class="sm:col-span-6">
            <.input
              field={@form[:name]}
              type="text"
              label="Name"
              autocomplete="off"
            />
          </div>
          <div class="sm:col-span-6">
            <.input
              field={@form[:address1]}
              type="text"
              label="Address"
              autocomplete="off"
            />
          </div>
          <div class="sm:col-span-6">
            <.input
              field={@form[:address2]}
              type="text"
              label="Apartment, suite, etc. (optional)"
              autocomplete="off"
            />
          </div>
          <div class="sm:col-span-3">
            <.input
              field={@form[:city]}
              type="text"
              label="City"
              autocomplete="off"
            />
          </div>
          <div class="sm:col-span-1">
            <.input
              field={@form[:state_code]}
              type="text"
              label="State"
              placeholder="CA"
              autocomplete="off"
            />
          </div>
          <div class="sm:col-span-2">
            <.input
              field={@form[:zip]}
              type="text"
              label="ZIP code"
              autocomplete="off"
            />
          </div>
          <div class="sm:col-span-3">
            <.input
              field={@form[:phone]}
              type="tel"
              label="Phone (optional)"
              autocomplete="off"
            />
          </div>
          <div class="sm:col-span-3">
            <.input
              field={@form[:email]}
              type="email"
              label="Email (optional)"
              autocomplete="off"
            />
          </div>
          <p class="text-sm text-zinc-500 sm:col-span-6">
            With an email, the recipient gets an order confirmation and shipping updates.
          </p>
        </div>
      </section>

      <section id="order-items" class="space-y-5">
        <h2 class="text-lg text-zinc-800 type-subhead">What are they getting?</h2>

        <div
          :for={key <- line_keys(@params)}
          id={"order-line-#{key}"}
          class="flex items-end gap-3"
        >
          <div class="min-w-0 flex-1">
            <.input
              type="select"
              id={"line-variant-#{key}"}
              name={"order[lines][#{key}][variant_id]"}
              value={@params["lines"][key]["variant_id"]}
              label="Item"
              prompt="Choose an item"
              options={@variant_options}
            />
          </div>
          <div class="w-28">
            <.input
              type="number"
              id={"line-quantity-#{key}"}
              name={"order[lines][#{key}][quantity]"}
              value={@params["lines"][key]["quantity"]}
              label="Quantity"
              min="1"
              max="500"
            />
          </div>
          <button
            :if={map_size(@params["lines"]) > 1}
            type="button"
            id={"remove-line-#{key}"}
            phx-click="remove_line"
            phx-value-key={key}
            aria-label="Remove this item"
            class="mb-0.5 inline-flex size-10 items-center justify-center rounded-sm text-zinc-500 transition hover:bg-zinc-100 hover:text-red-600"
          >
            <.icon name="hero-trash" class="size-5" />
          </button>
        </div>

        <p
          :if={@lines_error}
          id="lines-error"
          class="text-sm text-red-600"
          role="alert"
        >
          {@lines_error}
        </p>

        <.button
          type="button"
          id="add-line"
          phx-click="add_line"
          variant="outline"
          color="zinc"
        >
          <.icon name="hero-plus" class="size-4" /> Add another item
        </.button>
      </section>

      <section id="order-why" class="space-y-5">
        <h2 class="text-lg text-zinc-800 type-subhead">Why is the club paying?</h2>
        <.input
          field={@form[:purpose]}
          type="textarea"
          label="Purpose"
          placeholder="e.g. Giveaways for the October happy hour"
          rows="2"
          maxlength="500"
        />
        <.input
          field={@form[:event_id]}
          type="select"
          label="Event (optional)"
          options={@event_options}
        />
        <p class="text-sm text-zinc-500">
          Linking an event adds this order's cost to that event's Statistics tab.
        </p>
      </section>

      <div
        :if={@summary != []}
        id="order-problems"
        class="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800"
        role="alert"
      >
        <p class="font-semibold">Fix these to continue:</p>
        <ul class="mt-2 list-disc space-y-1 pl-5">
          <li :for={problem <- @summary}>{problem}</li>
        </ul>
      </div>

      <div class="flex justify-end gap-3 border-t border-zinc-200 pt-6">
        <.button
          id="cancel-order"
          navigate={~p"/admin/merch/orders"}
          variant="outline"
          color="zinc"
        >
          Cancel
        </.button>
        <.button type="submit" id="review-order" phx-disable-with="Checking…">
          Review order
        </.button>
      </div>
    </.form>
    """
  end

  attr :params, :map, required: true
  attr :address, :any, required: true
  attr :lines, :list, required: true
  attr :review, :any, default: nil
  attr :review_error, :string, default: nil
  attr :event_options, :list, required: true
  attr :placing?, :boolean, default: false

  defp review_step(assigns) do
    assigns =
      assign(
        assigns,
        :event,
        event_title(assigns.params, assigns.event_options)
      )

    ~H"""
    <div id="merch-order-review" class="space-y-10">
      <section class="space-y-4">
        <h2 class="text-lg text-zinc-800 type-subhead">Check the order</h2>

        <dl class="divide-y divide-zinc-200 rounded-lg border border-zinc-200 text-sm">
          <div class="grid grid-cols-3 gap-4 p-4">
            <dt class="text-zinc-500">Ship to</dt>
            <dd id="review-address" class="col-span-2 text-zinc-900">
              <.shipping_address_lines address={@address} name={@address.name} />
            </dd>
          </div>
          <div class="grid grid-cols-3 gap-4 p-4">
            <dt class="text-zinc-500">Items</dt>
            <dd id="review-items" class="col-span-2 text-zinc-900">
              <p :for={line <- @lines}>{line.quantity} × {line.variant.name}</p>
            </dd>
          </div>
          <div class="grid grid-cols-3 gap-4 p-4">
            <dt class="text-zinc-500">Why</dt>
            <dd id="review-purpose" class="col-span-2 text-zinc-900">
              {@params["purpose"]}
            </dd>
          </div>
          <div :if={@event} class="grid grid-cols-3 gap-4 p-4">
            <dt class="text-zinc-500">Event</dt>
            <dd id="review-event" class="col-span-2 text-zinc-900">{@event}</dd>
          </div>
        </dl>
      </section>

      <section id="review-cost" class="space-y-4">
        <h2 class="text-lg text-zinc-800 type-subhead">Shipping and cost</h2>

        <p
          :if={@review == :loading}
          id="review-loading"
          class="text-sm text-zinc-500"
        >
          Asking Printful for shipping options and a price…
        </p>

        <div
          :if={@review_error}
          id="review-error"
          class="rounded-lg bg-red-50 p-4 text-sm text-red-700"
          role="alert"
        >
          {@review_error}
          <button
            type="button"
            id="retry-review"
            phx-click="retry_review"
            class="ml-1 font-semibold underline"
          >
            Try again
          </button>
        </div>

        <div :if={is_map(@review)} class="space-y-4">
          <form id="shipping-form" phx-change="select_option">
            <.input
              type="select"
              id="shipping-option"
              name="shipping"
              value={@review.option.id}
              label="Shipping"
              options={shipping_options(@review.options)}
            />
          </form>

          <div class="rounded-lg bg-zinc-50 p-4 text-sm">
            <%= case @review.estimate do %>
              <% :loading -> %>
                <p id="estimate-loading" class="text-zinc-500">
                  Updating the price…
                </p>
              <% {:ok, estimate} -> %>
                <p class="text-zinc-600">Printful will charge the club about</p>
                <p
                  id="estimate-total"
                  class="type-title mt-1 text-3xl tabular-nums text-zinc-900"
                >
                  {Money.to_string!(estimate.total)}
                </p>
                <p :if={estimate.shipping} class="mt-1 text-zinc-500">
                  including {Money.to_string!(estimate.shipping)} shipping
                </p>
              <% _ -> %>
                <p id="estimate-unavailable" class="text-zinc-700">
                  Printful couldn't give a price right now. You can still place the order; its cost will show once Printful accepts it.
                </p>
            <% end %>
          </div>
        </div>

        <p class="text-sm text-zinc-500">
          Placing the order sends it to Printful right away and emails the board a summary with your name on it.
        </p>
      </section>

      <div class="flex justify-end gap-3 border-t border-zinc-200 pt-6">
        <.button
          type="button"
          id="back-to-details"
          phx-click="back"
          variant="outline"
          color="zinc"
        >
          Back
        </.button>
        <.button
          type="button"
          id="place-order"
          phx-click="place_order"
          disabled={!is_map(@review) or @review.estimate == :loading or @placing?}
          phx-disable-with="Placing…"
        >
          Place order
        </.button>
      </div>
    </div>
    """
  end
end
