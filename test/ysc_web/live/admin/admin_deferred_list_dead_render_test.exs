defmodule YscWeb.AdminDeferredListDeadRenderTest do
  @moduledoc false

  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.BookingsFixtures
  import Ysc.EventsFixtures
  import Ysc.MerchFixtures
  import Ysc.ScanningFixtures

  alias Ysc.Ledgers

  setup %{conn: conn} do
    user = user_fixture(%{role: "admin"})
    %{conn: log_in_user(conn, user), admin: user}
  end

  defp post_fixture(author, attrs) do
    {:ok, post} =
      %Ysc.Posts.Post{}
      |> Ysc.Posts.Post.new_post_changeset(
        Enum.into(attrs, %{
          user_id: author.id,
          title: "Test Post",
          url_name: "test-post-#{System.unique_integer()}",
          state: :published
        })
      )
      |> Ysc.Repo.insert()

    post
  end

  test "dead render skips posts list query and shows loading state", %{
    conn: conn,
    admin: admin
  } do
    post_fixture(admin, %{title: "Static Render Post"})

    posts_pattern = ~r/FROM "posts"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/posts")
          |> html_response(200)
        end,
        pattern: posts_pattern,
        caller_pids: [self()]
      )

    assert query_count == 0
    assert html =~ ~s|id="admin-posts-loading"|
    refute html =~ "Static Render Post"
  end

  test "dead render skips events list query and shows loading state", %{
    conn: conn,
    admin: admin
  } do
    event_fixture(%{title: "Static Render Event", organizer_id: admin.id})

    events_pattern = ~r/FROM "events"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/events")
          |> html_response(200)
        end,
        pattern: events_pattern,
        caller_pids: [self()]
      )

    assert query_count == 0
    assert html =~ ~s|id="admin-events-loading"|
    refute html =~ "Static Render Event"
  end

  test "dead render skips users list query and shows loading state", %{
    conn: conn
  } do
    user_fixture(%{first_name: "Static", last_name: "User"})

    users_pattern = ~r/FROM "users"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/users")
          |> html_response(200)
        end,
        pattern: users_pattern,
        caller_pids: [self()]
      )

    assert query_count == 0
    assert html =~ ~s|id="admin-users-loading"|
    refute html =~ "Static User"
  end

  test "dead render loads review route with deferred modal content", %{
    conn: conn
  } do
    pending_user =
      user_fixture(%{
        state: "pending_approval",
        first_name: "Review",
        last_name: "Render"
      })

    signup_application_fixture(pending_user)

    html =
      conn
      |> get("/admin/users/#{pending_user.id}/review")
      |> html_response(200)

    assert html =~ ~s|id="admin-user-review-modal-loading"|
    assert html =~ ~s|id="admin-users-loading"|
    refute html =~ "Review Application"
    refute html =~ "Review Render"
  end

  test "dead render skips scanner sessions query and shows loading state", %{
    conn: conn,
    admin: admin
  } do
    scan_session_fixture(%{
      created_by_id: admin.id,
      name: "Static Render Session"
    })

    sessions_pattern = ~r/FROM "scan_sessions"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/scanner/sessions")
          |> html_response(200)
        end,
        pattern: sessions_pattern,
        caller_pids: [self()]
      )

    assert query_count == 0
    assert html =~ "Loading sessions"
    refute html =~ "Static Render Session"
  end

  test "dead render skips scanner session detail query and shows loading state",
       %{
         conn: conn,
         admin: admin
       } do
    session =
      scan_session_fixture(%{
        created_by_id: admin.id,
        name: "Static Detail Session"
      })

    sessions_pattern = ~r/FROM "scan_sessions"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/scanner/sessions/#{session.id}")
          |> html_response(200)
        end,
        pattern: sessions_pattern,
        caller_pids: [self()]
      )

    assert query_count == 0
    assert html =~ "Loading session"
    refute html =~ "Static Detail Session"
  end

  test "dead render skips event check-in event query and shows loading shell",
       %{
         conn: conn,
         admin: admin
       } do
    event =
      event_fixture(%{
        organizer_id: admin.id,
        title: "Static Render Check-in Event",
        state: :published
      })

    events_pattern = ~r/FROM "events"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/events/#{event.id}/check-in")
          |> html_response(200)
        end,
        pattern: events_pattern,
        caller_pids: [self()]
      )

    assert query_count == 0
    assert html =~ ~s|id="check-in-search-form"|
    refute html =~ "Static Render Check-in Event"
  end

  test "dead render skips newsletter edition query and shows loading state", %{
    conn: conn,
    admin: admin
  } do
    {:ok, edition} =
      Ysc.Newsletter.create_edition(
        %{"title" => "Static Render Edition", "subject" => "Weekly news"},
        created_by_id: admin.id
      )

    editions_pattern = ~r/FROM "newsletter_editions"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/newsletters/#{edition.id}/edit")
          |> html_response(200)
        end,
        pattern: editions_pattern,
        caller_pids: [self()]
      )

    assert query_count == 0
    assert html =~ "Loading newsletter"
    refute html =~ "Static Render Edition"
  end

  test "dead render skips payment modal queries on payment detail route", %{
    conn: conn
  } do
    Ledgers.ensure_basic_accounts()
    payment = Ysc.LedgersFixtures.payment_fixture()

    payments_pattern = ~r/FROM "payments"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/money/payments/#{payment.id}")
          |> html_response(200)
        end,
        pattern: payments_pattern,
        caller_pids: [self()]
      )

    assert query_count == 0
    assert html =~ "Money Management"
    refute html =~ ~s(id="payment-modal")
  end

  test "dead render skips refund modal queries on refund route", %{conn: conn} do
    Ledgers.ensure_basic_accounts()
    payment = Ysc.LedgersFixtures.payment_fixture()

    refunds_pattern = ~r/FROM "refunds"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/money/payments/#{payment.id}/refund")
          |> html_response(200)
        end,
        pattern: refunds_pattern,
        caller_pids: [self()]
      )

    assert query_count == 0
    assert html =~ "Money Management"
    refute html =~ ~s(id="refund-modal")
  end

  test "dead render skips booking modal queries on booking detail route", %{
    conn: conn
  } do
    user = user_fixture()
    booking = booking_fixture(%{user_id: user.id, property: :tahoe})

    bookings_pattern = ~r/FROM "bookings"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/bookings/#{booking.id}")
          |> html_response(200)
        end,
        pattern: bookings_pattern,
        caller_pids: [self()]
      )

    assert query_count == 0
    assert html =~ "Bookings"
    refute html =~ ~s(id="booking-modal")
  end

  test "dead render skips merch catalog query and shows loading state", %{
    conn: conn
  } do
    product_fixture(%{name: "Static Render Merch"})

    merch_pattern = ~r/FROM "(merch_products|merch_orders)"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/merch")
          |> html_response(200)
        end,
        pattern: merch_pattern,
        caller_pids: [self()]
      )

    assert query_count == 0
    assert html =~ ~s|id="admin-merch-loading"|
    refute html =~ "Static Render Merch"
    refute html =~ ~s|id="merch-empty"|
  end

  test "dead render skips merch orders list query and shows loading state", %{
    conn: conn,
    admin: admin
  } do
    admin_order_fixture(admin, %{recipient_name: "Static Render Recipient"})

    orders_pattern = ~r/FROM "merch_orders"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/merch/orders")
          |> html_response(200)
        end,
        pattern: orders_pattern,
        caller_pids: [self()]
      )

    assert query_count == 0
    assert html =~ ~s|id="admin-merch-orders-loading"|
    refute html =~ "Static Render Recipient"
    refute html =~ ~s|id="admin_merch_orders_list"|
  end

  test "dead render skips merch order detail query and shows loading state", %{
    conn: conn,
    admin: admin
  } do
    order = admin_order_fixture(admin)

    orders_pattern = ~r/FROM "merch_orders"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/merch/orders/#{order.id}")
          |> html_response(200)
        end,
        pattern: orders_pattern,
        caller_pids: [self()]
      )

    assert query_count == 0
    assert html =~ ~s|id="admin-merch-order-loading"|
    refute html =~ order.reference_id
    refute html =~ ~s|id="order-detail"|
  end

  test "dead render skips club-paid order form queries and shows loading state",
       %{
         conn: conn
       } do
    variant_fixture(nil, %{name: "Static Render Tee"})
    event_fixture(%{title: "Static Render Merch Event"})

    products_pattern = ~r/FROM "merch_products"/i

    {html, query_count} =
      Ysc.QueryCounter.with_query_counter(
        fn ->
          conn
          |> get("/admin/merch/orders/new")
          |> html_response(200)
        end,
        pattern: products_pattern,
        caller_pids: [self()]
      )

    assert query_count == 0
    assert html =~ ~s|id="admin-merch-order-new-loading"|
    refute html =~ "Static Render Tee"
    refute html =~ ~s|id="merch-order-form"|
  end

  describe "connected list loading" do
    test "newsletter editor replaces loading placeholder after connect", %{
      conn: conn,
      admin: admin
    } do
      {:ok, edition} =
        Ysc.Newsletter.create_edition(
          %{"title" => "Deferred Load Edition", "subject" => "Weekly news"},
          created_by_id: admin.id
        )

      {:ok, view, _html} = live(conn, ~p"/admin/newsletters/#{edition.id}/edit")
      html = render_async(view)

      refute html =~ "Loading newsletter"
      assert html =~ "Deferred Load Edition"
      assert has_element?(view, "#newsletter-editor-form")
    end

    test "events list replaces loading placeholder after connect", %{
      conn: conn,
      admin: admin
    } do
      event_fixture(%{title: "Deferred Load Event", organizer_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/events")
      html = render(view)

      refute html =~ "Loading events…"
      assert html =~ "Deferred Load Event"
      assert has_element?(view, "#admin_events_list")
    end

    test "posts list replaces loading placeholder after connect", %{
      conn: conn,
      admin: admin
    } do
      post_fixture(admin, %{title: "Deferred Load Post"})

      {:ok, view, _html} = live(conn, ~p"/admin/posts")
      html = render(view)

      refute html =~ "Loading posts…"
      assert html =~ "Deferred Load Post"
      assert has_element?(view, "#admin_posts_list")
    end

    test "users list replaces loading placeholder after connect", %{conn: conn} do
      user_fixture(%{first_name: "Deferred", last_name: "Loaduser"})

      {:ok, view, _html} = live(conn, ~p"/admin/users")
      html = render(view)

      refute html =~ "Loading users…"
      assert html =~ "Deferred Loaduser"
      assert has_element?(view, "#admin_users_list")
    end

    test "review modal replaces loading placeholder after connect", %{
      conn: conn
    } do
      pending_user =
        user_fixture(%{
          state: "pending_approval",
          first_name: "Review",
          last_name: "Connect"
        })

      signup_application_fixture(pending_user)

      {:ok, view, _html} =
        live(conn, ~p"/admin/users/#{pending_user.id}/review")

      html = render_async(view)

      refute html =~ ~s|id="admin-user-review-modal-loading"|
      assert html =~ "Review Application"
      assert html =~ "Review Connect"
    end

    test "merch catalog replaces loading placeholder after connect", %{
      conn: conn
    } do
      product_fixture(%{name: "Deferred Load Merch"})

      {:ok, view, _html} = live(conn, ~p"/admin/merch")
      html = render(view)

      refute html =~ ~s|id="admin-merch-loading"|
      assert html =~ "Deferred Load Merch"
      assert has_element?(view, "#admin_merch_products_list")
    end

    test "merch orders list replaces loading placeholder after connect", %{
      conn: conn,
      admin: admin
    } do
      order =
        admin_order_fixture(admin, %{recipient_name: "Deferred Load Recipient"})

      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders")
      html = render(view)

      refute html =~ ~s|id="admin-merch-orders-loading"|
      assert html =~ "Deferred Load Recipient"
      assert has_element?(view, "#admin_merch_orders_list-row-#{order.id}")
    end

    test "merch order detail replaces loading placeholder after connect", %{
      conn: conn,
      admin: admin
    } do
      order = admin_order_fixture(admin)

      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/#{order.id}")
      html = render(view)

      refute html =~ ~s|id="admin-merch-order-loading"|
      assert html =~ order.reference_id
      assert has_element?(view, "#order-detail")
    end

    test "club-paid order form replaces loading placeholder after connect", %{
      conn: conn
    } do
      variant_fixture(nil, %{name: "Deferred Load Tee"})

      {:ok, view, _html} = live(conn, ~p"/admin/merch/orders/new")
      html = render(view)

      refute html =~ ~s|id="admin-merch-order-new-loading"|
      assert html =~ "Deferred Load Tee"
      assert has_element?(view, "#merch-order-form")
    end
  end
end
