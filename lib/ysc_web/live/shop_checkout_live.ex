defmodule YscWeb.ShopCheckoutLive do
  @moduledoc """
  Merch checkout, in three steps on one page: delivery address, shipping
  method (priced live by Printful), and payment through Stripe.

  Totals are always recomputed on the server from the catalog and Printful's
  quote; nothing monetary is trusted from the browser.
  """
  use YscWeb, :live_view

  on_mount {YscWeb.ShopAccess, :ensure_member}

  import Ysc.MoneyHelper, only: [format_price: 1]
  import YscWeb.ShopComponents

  alias Ysc.Merch.{
    Cart,
    Fulfillment,
    Orders,
    Shipping,
    ShippingAddress,
    StripeService
  }

  alias Ysc.Repo

  @impl true
  def mount(_params, _session, socket) do
    user = Repo.preload(socket.assigns.current_user, :billing_address)
    lines = user |> Cart.list() |> Cart.available_lines()

    if lines == [] do
      {:ok,
       socket
       |> YscWeb.Flash.put_toast(:info, "Your cart is empty.", title: "Shop")
       |> push_navigate(to: ~p"/shop/cart")}
    else
      {:ok,
       socket
       |> assign(:page_title, "Checkout")
       |> assign(:current_user, user)
       |> assign(:lines, lines)
       |> assign(:subtotal, Cart.subtotal(lines))
       |> assign(:cart_count, Cart.item_count(lines))
       |> assign(:step, :address)
       |> assign(
         :form,
         to_form(
           ShippingAddress.changeset(ShippingAddress.from_user(user), %{}),
           as: :address
         )
       )
       |> assign(:address, nil)
       |> assign(:shipping_options, [])
       |> assign(:selected_option, nil)
       |> assign(:quoting?, false)
       |> assign(:preparing_payment?, false)
       |> assign(:address_error, nil)
       |> assign(:shipping_error, nil)
       |> assign(:payment_error, nil)
       |> assign(:order, nil)
       |> assign(:payment_intent, nil)
       |> assign(:stripe_payment_element_ready, false)
       |> assign(
         :stripe_billing_details,
         Ysc.Customers.payment_element_default_values_json(user)
       )}
    end
  end

  ## Address

  @impl true
  def handle_event("validate_address", %{"address" => params}, socket) do
    form =
      %ShippingAddress{}
      |> ShippingAddress.changeset(params)
      |> Map.put(:action, :validate)
      |> to_form(as: :address)

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("submit_address", %{"address" => params}, socket) do
    case ShippingAddress.validate(params) do
      {:ok, address} ->
        lines = socket.assigns.lines

        {:noreply,
         socket
         |> assign(:address, address)
         |> assign(:address_error, nil)
         |> assign(:quoting?, true)
         |> start_async(:quote_shipping, fn ->
           Shipping.options(address, lines)
         end)}

      {:error, changeset} ->
        {:noreply,
         assign(
           socket,
           :form,
           to_form(%{changeset | action: :validate}, as: :address)
         )}
    end
  end

  def handle_event("edit_address", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :address)
     |> assign(:payment_intent, nil)
     |> assign(:stripe_payment_element_ready, false)}
  end

  ## Shipping

  def handle_event("select_shipping", %{"id" => id}, socket) do
    option = Enum.find(socket.assigns.shipping_options, &(&1.id == id))

    {:noreply,
     if(option, do: assign(socket, :selected_option, option), else: socket)}
  end

  def handle_event("edit_shipping", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :shipping)
     |> assign(:payment_intent, nil)
     |> assign(:stripe_payment_element_ready, false)}
  end

  def handle_event(
        "continue_to_payment",
        _params,
        %{assigns: %{selected_option: nil}} = socket
      ) do
    {:noreply,
     assign(socket, :shipping_error, "Choose a shipping method to continue.")}
  end

  def handle_event(
        "continue_to_payment",
        _params,
        %{assigns: %{preparing_payment?: true}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event("continue_to_payment", _params, socket) do
    %{current_user: user, address: address, selected_option: option} =
      socket.assigns

    {:noreply,
     socket
     |> assign(:preparing_payment?, true)
     |> assign(:shipping_error, nil)
     |> start_async(:prepare_payment, fn ->
       prepare_payment(user, address, option)
     end)}
  end

  ## Payment

  def handle_event("stripe-payment-element-loading", _params, socket) do
    {:noreply, assign(socket, :stripe_payment_element_ready, false)}
  end

  def handle_event("stripe-payment-element-ready", _params, socket) do
    {:noreply, assign(socket, :stripe_payment_element_ready, true)}
  end

  def handle_event("payment-redirect-started", _params, socket),
    do: {:noreply, socket}

  def handle_event(
        "payment-success",
        %{"payment_intent_id" => payment_intent_id},
        socket
      ) do
    order = socket.assigns.order

    # The Stripe webhook usually gets here first; both paths are idempotent.
    # If Stripe hasn't settled yet, the confirmation page keeps checking.
    case Fulfillment.process_successful_payment(payment_intent_id) do
      {:ok, _paid} -> :ok
      {:error, _reason} -> :ok
    end

    {:noreply,
     push_navigate(socket, to: ~p"/shop/orders/#{order.id}/confirmation")}
  end

  ## Async results

  @impl true
  def handle_async(:quote_shipping, {:ok, {:ok, options}}, socket) do
    {:noreply,
     socket
     |> assign(:quoting?, false)
     |> assign(:shipping_options, options)
     |> assign(:selected_option, List.first(options))
     |> assign(:shipping_error, nil)
     |> assign(:step, :shipping)}
  end

  def handle_async(
        :quote_shipping,
        {:ok, {:error, {:rejected, message}}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:quoting?, false)
     |> assign(:address_error, "We couldn't ship to that address: #{message}")}
  end

  def handle_async(:quote_shipping, _failure, socket) do
    {:noreply,
     socket
     |> assign(:quoting?, false)
     |> assign(
       :address_error,
       "We couldn't get shipping prices right now. Please try again in a moment."
     )}
  end

  def handle_async(
        :prepare_payment,
        {:ok, {:ok, order, payment_intent}},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:preparing_payment?, false)
     |> assign(:order, order)
     |> assign(:payment_intent, payment_intent)
     |> assign(:payment_error, nil)
     |> assign(:step, :payment)}
  end

  def handle_async(:prepare_payment, {:ok, {:paid, order}}, socket) do
    {:noreply,
     push_navigate(socket, to: ~p"/shop/orders/#{order.id}/confirmation")}
  end

  def handle_async(:prepare_payment, {:ok, {:error, message}}, socket) do
    {:noreply,
     socket
     |> assign(:preparing_payment?, false)
     |> assign(:shipping_error, message)}
  end

  def handle_async(:prepare_payment, _failure, socket) do
    {:noreply,
     socket
     |> assign(:preparing_payment?, false)
     |> assign(
       :shipping_error,
       "Something went wrong setting up payment. Please try again."
     )}
  end

  # Runs off the LiveView process: re-reads the cart so the order reflects
  # exactly what is in it now, then opens the payment.
  defp prepare_payment(user, address, option) do
    lines = user |> Cart.list() |> Cart.available_lines()

    with {:ok, order} <-
           Orders.create_pending_purchase(user, lines, address, option),
         {:ok, intent} <- StripeService.ensure_payment_intent(order, user) do
      if intent.status == "succeeded" do
        {:paid, order}
      else
        {:ok, order, intent}
      end
    else
      {:error, :empty_cart} ->
        {:error, "Your cart is empty."}

      {:error, :unavailable_items} ->
        {:error,
         "An item in your cart is no longer available. Review your cart and try again."}

      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, _other} ->
        {:error, "We couldn't set up your order. Please try again."}
    end
  end

  ## Render

  @impl true
  def render(assigns) do
    ~H"""
    <.shop_frame
      id="shop-checkout-page"
      title="Checkout"
      active={:cart}
      cart_count={@cart_count}
    >
      <div class="grid grid-cols-1 gap-12 lg:grid-cols-5 lg:gap-16">
        <div class="space-y-12 lg:col-span-3">
          <section>
            <.step_heading id="step-address" step={1}>
              Delivery address
            </.step_heading>
            <.address_step
              :if={@step == :address}
              form={@form}
              address_error={@address_error}
              quoting?={@quoting?}
            />
            <.address_summary :if={@step != :address} address={@address} />
          </section>

          <section :if={@step in [:shipping, :payment]}>
            <.step_heading id="step-shipping" step={2}>
              Shipping method
            </.step_heading>
            <.shipping_step
              :if={@step == :shipping}
              shipping_options={@shipping_options}
              selected_option={@selected_option}
              shipping_error={@shipping_error}
              preparing_payment?={@preparing_payment?}
            />
            <.shipping_summary :if={@step == :payment} option={@selected_option} />
          </section>

          <section :if={@step == :payment}>
            <.step_heading id="step-payment" step={3}>Payment</.step_heading>
            <.payment_step
              order={@order}
              payment_intent={@payment_intent}
              stripe_billing_details={@stripe_billing_details}
              stripe_payment_element_ready={@stripe_payment_element_ready}
            />
          </section>
        </div>

        <aside class="lg:col-span-2">
          <.cart_summary
            lines={@lines}
            subtotal={@subtotal}
            option={@selected_option}
            step={@step}
          />
        </aside>
      </div>
    </.shop_frame>
    """
  end

  attr :form, :any, required: true
  attr :address_error, :string, default: nil
  attr :quoting?, :boolean, default: false

  defp address_step(assigns) do
    ~H"""
    <div id="checkout-address" class="mt-6 space-y-5">
      <p class="text-zinc-500">We currently ship within the United States.</p>

      <p
        :if={@address_error}
        id="address-error"
        class="rounded-2xl bg-red-50 p-4 text-sm text-red-700"
        role="alert"
      >
        {@address_error}
      </p>

      <.form
        for={@form}
        id="address-form"
        phx-change="validate_address"
        phx-submit="submit_address"
        class="space-y-5"
      >
        <.input
          field={@form[:name]}
          type="text"
          label="Full name"
          autocomplete="name"
        />
        <.input
          field={@form[:address1]}
          type="text"
          label="Address"
          autocomplete="address-line1"
        />
        <.input
          field={@form[:address2]}
          type="text"
          label="Apartment, suite, etc. (optional)"
          autocomplete="address-line2"
        />
        <div class="grid grid-cols-1 gap-5 sm:grid-cols-3">
          <.input
            field={@form[:city]}
            type="text"
            label="City"
            autocomplete="address-level2"
          />
          <.input
            field={@form[:state_code]}
            type="select"
            label="State"
            prompt="Select"
            options={ShippingAddress.states()}
            autocomplete="address-level1"
          />
          <.input
            field={@form[:zip]}
            type="text"
            label="ZIP code"
            autocomplete="postal-code"
          />
        </div>
        <.input
          field={@form[:phone]}
          type="tel"
          label="Phone (for the carrier)"
          autocomplete="tel"
        />
        <input type="hidden" name="address[country_code]" value="US" />
        <input type="hidden" name="address[email]" value={@form[:email].value} />

        <div class="flex justify-end">
          <.button
            id="submit-address"
            type="submit"
            disabled={@quoting?}
            class="h-12 w-full motion-safe:active:scale-[0.98] sm:w-auto sm:px-10"
          >
            {if @quoting?,
              do: "Getting shipping prices…",
              else: "Continue to shipping"}
          </.button>
        </div>
      </.form>
    </div>
    """
  end

  attr :address, :any, required: true

  defp address_summary(assigns) do
    ~H"""
    <div
      id="checkout-address-summary"
      class="mt-4 flex items-start justify-between gap-4"
    >
      <p class="text-lg text-zinc-700">
        {@address.name}<br />
        {@address.address1}<br />
        <span :if={@address.address2 not in [nil, ""]}>{@address.address2}<br /></span>
        {@address.city}, {@address.state_code} {@address.zip}
      </p>
      <button
        type="button"
        id="edit-address"
        phx-click="edit_address"
        class="inline-flex min-h-11 items-center text-sm font-medium text-blue-600 hover:text-blue-800"
      >
        Edit
      </button>
    </div>
    """
  end

  attr :shipping_options, :list, required: true
  attr :selected_option, :any, default: nil
  attr :shipping_error, :string, default: nil
  attr :preparing_payment?, :boolean, default: false

  defp shipping_step(assigns) do
    ~H"""
    <div id="checkout-shipping" class="mt-6 space-y-5">
      <fieldset class="space-y-3">
        <legend class="sr-only">Shipping method</legend>
        <label
          :for={option <- @shipping_options}
          id={"shipping-option-#{option.id}"}
          class={[
            "flex cursor-pointer items-center gap-4 rounded-2xl p-5 transition motion-safe:active:scale-[0.99]",
            if(@selected_option && @selected_option.id == option.id,
              do: "bg-white shadow-md ring-2 ring-blue-600",
              else: "bg-zinc-50 hover:bg-zinc-100"
            )
          ]}
        >
          <input
            type="radio"
            name="shipping_option"
            value={option.id}
            checked={@selected_option && @selected_option.id == option.id}
            phx-click="select_shipping"
            phx-value-id={option.id}
            class="size-4 text-blue-600"
          />
          <span class="flex-1">
            <span class="block text-lg text-zinc-900">{option.name}</span>
            <span :if={show_window?(option)} class="block text-zinc-500">
              {Shipping.delivery_window(option)}
            </span>
          </span>
          <span class="text-lg text-zinc-900">{format_price(option.rate)}</span>
        </label>
      </fieldset>

      <p
        :if={@shipping_error}
        id="shipping-error"
        class="rounded-2xl bg-red-50 p-4 text-sm text-red-700"
        role="alert"
      >
        {@shipping_error}
      </p>

      <div class="flex justify-end">
        <.button
          id="continue-to-payment"
          type="button"
          phx-click="continue_to_payment"
          disabled={@preparing_payment?}
          class="h-12 w-full sm:w-auto sm:px-10"
        >
          {if @preparing_payment?,
            do: "Preparing payment…",
            else: "Continue to payment"}
        </.button>
      </div>
    </div>
    """
  end

  attr :option, :any, required: true

  defp shipping_summary(assigns) do
    ~H"""
    <div
      id="checkout-shipping-summary"
      class="mt-4 flex items-start justify-between gap-4"
    >
      <p class="text-lg text-zinc-700">
        {@option.name} · {format_price(@option.rate)}
        <span :if={show_window?(@option)} class="text-zinc-500">
          ({Shipping.delivery_window(@option)})
        </span>
      </p>
      <button
        type="button"
        id="edit-shipping"
        phx-click="edit_shipping"
        class="inline-flex min-h-11 items-center text-sm font-medium text-blue-600 hover:text-blue-800"
      >
        Edit
      </button>
    </div>
    """
  end

  attr :order, :any, required: true
  attr :payment_intent, :any, required: true
  attr :stripe_billing_details, :string, required: true
  attr :stripe_payment_element_ready, :boolean, default: false

  defp payment_step(assigns) do
    ~H"""
    <div id="checkout-payment" class="mt-6 space-y-6">
      <div
        id="stripe-payment-container"
        phx-hook="StripeElements"
        data-client-secret={@payment_intent.client_secret}
        data-return-path={~p"/shop/orders/#{@order.id}/confirmation"}
        data-billing-details={@stripe_billing_details}
      >
        <.payment_element_loading :if={!@stripe_payment_element_ready} />
        <div id="payment-element" phx-update="ignore" class="mb-6 min-h-48"></div>
        <div id="payment-message" class="mt-4 hidden"></div>
      </div>

      <div class="flex justify-end">
        <.button
          id="submit-payment"
          type="button"
          disabled={!@stripe_payment_element_ready}
          class="h-12 w-full text-lg motion-safe:active:scale-[0.98] sm:w-auto sm:px-10"
        >
          <.icon name="hero-lock-closed" class="size-5" />
          Pay {format_price(@order.total_amount)} securely
        </.button>
      </div>
    </div>
    """
  end

  attr :lines, :list, required: true
  attr :subtotal, :any, required: true
  attr :option, :any, default: nil
  attr :step, :atom, required: true

  defp cart_summary(assigns) do
    ~H"""
    <section
      id="checkout-summary"
      class="rounded-3xl bg-zinc-50 p-8 lg:sticky lg:top-28"
    >
      <h2 class="type-subhead text-xl text-zinc-900">Your order</h2>

      <ul class="mt-6 space-y-5">
        <li
          :for={line <- @lines}
          id={"summary-line-#{line.variant.id}"}
          class="flex items-center gap-4"
        >
          <.shop_thumb
            image={line.variant.image}
            fallback_image={line.product.image}
            class="size-16"
          />
          <div class="min-w-0 flex-1">
            <p class="truncate text-zinc-900">{line.product.name}</p>
            <p class="truncate text-sm text-zinc-500">
              {line.variant.name} × {line.quantity}
            </p>
          </div>
          <p class="text-zinc-900">{format_price(line.line_total)}</p>
        </li>
      </ul>

      <dl class="mt-8 space-y-2 text-sm">
        <div class="flex justify-between text-zinc-600">
          <dt>Subtotal</dt>
          <dd id="summary-subtotal">{format_price(@subtotal)}</dd>
        </div>
        <div class="flex justify-between text-zinc-600">
          <dt>Shipping</dt>
          <dd id="summary-shipping">
            {if @option && @step in [:shipping, :payment],
              do: format_price(@option.rate),
              else: "Calculated next"}
          </dd>
        </div>
        <div
          :if={@option && @step in [:shipping, :payment]}
          class="flex justify-between pt-2 text-lg font-semibold text-zinc-900"
        >
          <dt>Total</dt>
          <dd id="summary-total">
            {format_price(Money.add!(@subtotal, @option.rate))}
          </dd>
        </div>
      </dl>
    </section>
    """
  end

  # Printful's own names usually already say "(3-5 business days)".
  defp show_window?(option) do
    Shipping.delivery_window(option) != nil and
      not String.contains?(String.downcase(option.name), "day")
  end
end
