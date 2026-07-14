defmodule YscWeb.UserTicketsLiveCancelTest do
  @moduledoc """
  Cancel-order behavior for `UserTicketsLive`, including the #692 guard that
  blocks cancellation while Stripe checkout payment is in flight.
  """
  use YscWeb.ConnCase, async: false

  import Mox
  import Phoenix.LiveViewTest
  import Ysc.TicketsFixtures

  alias Ysc.Tickets

  setup :verify_on_exit!

  setup do
    Ysc.Ledgers.ensure_basic_accounts()

    original_stripe_client = Application.get_env(:ysc, :stripe_client)
    Application.put_env(:ysc, :stripe_client, Ysc.StripeMock)

    on_exit(fn ->
      Application.put_env(:ysc, :stripe_client, original_stripe_client)
    end)

    :ok
  end

  describe "cancel-order event" do
    test "shows processing message when checkout payment is in flight", %{
      conn: conn
    } do
      order = ticket_order_fixture()
      payment_intent_id = "pi_processing_user_cancel_#{order.id}"

      assert {:ok, order} =
               Tickets.update_payment_intent(order, payment_intent_id)

      expect(Ysc.StripeMock, :retrieve_payment_intent, fn ^payment_intent_id,
                                                          _opts ->
        {:ok,
         %Stripe.PaymentIntent{
           id: payment_intent_id,
           status: "processing",
           amount: 2500
         }}
      end)

      conn = log_in_user(conn, Ysc.Accounts.get_user!(order.user_id))

      {:ok, view, _html} = live(conn, ~p"/users/tickets")

      render_click(view, "cancel-order", %{"order-id" => order.id})

      flash = :sys.get_state(view.pid).socket.assigns.flash
      error = Phoenix.Flash.get(flash, :error)

      assert error =~ "Your payment is still processing"
      assert error =~ "If you were charged"
      assert Ysc.Repo.get!(Ysc.Tickets.TicketOrder, order.id).status == :pending
    end
  end
end
