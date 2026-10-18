defmodule YscWeb.ShopCartPeek do
  @moduledoc """
  State for the floating cart dock's "added to cart" card.

  The card opens when something is added and closes itself after a few
  seconds. It never traps the member: it can be dismissed, pauses while the
  pointer is on it, and a second add simply retargets it to the new item.

  Every scheduled close carries a token. Opening, pausing or dismissing
  invalidates earlier tokens, so a stale timer can never close a card the
  member has since touched or that now shows something newer.

  Import into a LiveView and call from its callbacks:

      def handle_event("dismiss_cart_peek", _, socket), do: {:noreply, dismiss(socket)}
      def handle_info({:hide_cart_peek, token}, socket), do: {:noreply, hide_if_current(socket, token)}
  """
  import Phoenix.Component, only: [assign: 3]

  alias Ysc.Merch.Cart

  @open_ms 5_000
  @resume_ms 2_500

  @doc "Initial assigns: the dock's summary, with the card closed."
  def init(socket, user) do
    socket
    |> assign(:cart_summary, Cart.summary(user))
    |> assign_peek_defaults()
  end

  @doc """
  Placeholder dock assigns with no database round-trip.

  Used while a LiveView paints its first HTML before the catalog (and cart
  summary) load after the WebSocket connects.
  """
  def init_placeholder(socket) do
    socket
    |> assign(:cart_summary, Cart.summary(nil))
    |> assign_peek_defaults()
  end

  defp assign_peek_defaults(socket) do
    socket
    |> assign(:cart_peek, nil)
    |> assign(:cart_peek_open?, false)
    |> assign(:cart_peek_token, 0)
  end

  @doc "Refreshes the pill's count and subtotal."
  def refresh_summary(socket, user),
    do: assign(socket, :cart_summary, Cart.summary(user))

  @doc """
  Opens the card on `item` (a map with `:name`, `:detail`, `:image`,
  `:quantity`) and schedules it to close.
  """
  def show(socket, user, item) do
    socket
    |> refresh_summary(user)
    |> assign(:cart_peek, item)
    |> assign(:cart_peek_open?, true)
    |> schedule_close(@open_ms)
  end

  @doc "Closes the card now."
  def dismiss(socket) do
    socket |> invalidate() |> assign(:cart_peek_open?, false)
  end

  @doc "Keeps the card open while the pointer is on it."
  def pause(socket), do: invalidate(socket)

  @doc "Starts a shorter countdown once the pointer leaves."
  def resume(%{assigns: %{cart_peek_open?: true}} = socket),
    do: schedule_close(socket, @resume_ms)

  def resume(socket), do: socket

  @doc "Closes the card if `token` is still the latest one."
  def hide_if_current(%{assigns: %{cart_peek_token: token}} = socket, token) do
    assign(socket, :cart_peek_open?, false)
  end

  def hide_if_current(socket, _stale_token), do: socket

  defp schedule_close(socket, after_ms) do
    socket = invalidate(socket)

    Process.send_after(
      self(),
      {:hide_cart_peek, socket.assigns.cart_peek_token},
      after_ms
    )

    socket
  end

  defp invalidate(socket) do
    assign(
      socket,
      :cart_peek_token,
      System.unique_integer([:positive, :monotonic])
    )
  end
end
