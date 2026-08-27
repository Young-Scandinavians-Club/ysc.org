defmodule YscWeb.NewsletterArchiveLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.{Newsletter, Repo}

  defp clear_newsletter_rate_limit do
    :ets.delete_all_objects(Ysc.NewsletterRateLimit)
  end

  defp insert_sent_edition(creator, attrs) do
    base = %{
      "title" => "Weekly",
      "subject" => "Hello",
      "intro_text" => "<p>Intro snippet for list view.</p>"
    }

    {:ok, edition} =
      Newsletter.create_edition(Map.merge(base, attrs),
        created_by_id: creator.id
      )

    sent_at = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, edition} =
      Newsletter.update_edition(edition, %{
        status: :sent,
        sent_at: sent_at
      })

    edition
  end

  describe "index" do
    test "renders title and guest subscribe form when not logged in", %{
      conn: conn
    } do
      {:ok, view, html} = live(conn, ~p"/newsletters")

      assert html =~ "Newsletters"
      assert has_element?(view, "#newsletter-subscribe-form")
    end

    test "shows empty state after async load when no editions exist", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/newsletters")
      html = render_async(view)

      assert html =~ "No newsletters have been sent yet."
    end

    test "lists sent editions after async load", %{conn: conn} do
      admin = user_fixture()
      edition = insert_sent_edition(admin, %{"title" => "Spring Roundup"})

      {:ok, view, _html} = live(conn, ~p"/newsletters")
      html = render_async(view)

      assert html =~ "Spring Roundup"
      assert has_element?(view, ~s|a[href="/newsletters/#{edition.id}"]|)
    end

    test "omits excerpt line when intro_text is empty", %{conn: conn} do
      admin = user_fixture()

      _edition =
        insert_sent_edition(admin, %{
          "title" => "No Intro #{System.unique_integer()}",
          "intro_text" => ""
        })

      {:ok, view, _html} = live(conn, ~p"/newsletters")
      html = render_async(view)

      refute html =~ "Intro snippet for list view"
    end

    test "guest can submit subscribe form", %{conn: conn} do
      email = "newsletter_sub_#{System.unique_integer([:positive])}@example.com"

      {:ok, view, _html} = live(conn, ~p"/newsletters")
      render_async(view)

      html =
        view
        |> form("#newsletter-subscribe-form", %{"email" => email})
        |> render_submit()

      # Double opt-in: form submission sends a confirmation email rather
      # than subscribing immediately.
      assert html =~ "Check your email"
      refute Newsletter.get_subscriber_by_email(email).subscribed
    end

    test "guest subscribe shows error for invalid email", %{conn: conn} do
      clear_newsletter_rate_limit()

      {:ok, view, _html} = live(conn, ~p"/newsletters")
      render_async(view)

      html =
        view
        |> form("#newsletter-subscribe-form", %{"email" => "not-valid"})
        |> render_submit()

      assert has_element?(view, "#newsletter-error")
      assert html =~ "valid email"
    end

    test "subscribe_newsletter shows error for disposable email domain", %{
      conn: conn
    } do
      clear_newsletter_rate_limit()

      {:ok, view, _html} = live(conn, ~p"/newsletters")
      render_async(view)

      html =
        view
        |> form("#newsletter-subscribe-form", %{
          "email" => "test@mailinator.com"
        })
        |> render_submit()

      assert has_element?(view, "#newsletter-error")

      assert html =~
               "Temporary email addresses are not allowed. Please use a permanent email address."
    end

    test "subscribe_newsletter shows error for domain with no MX records", %{
      conn: conn
    } do
      clear_newsletter_rate_limit()

      {:ok, view, _html} = live(conn, ~p"/newsletters")
      stub_mx_no_records(view)
      render_async(view)

      domain = "mx-reject-#{System.unique_integer([:positive])}.example.org"

      html =
        view
        |> form("#newsletter-subscribe-form", %{"email" => "user@#{domain}"})
        |> render_submit()

      assert has_element?(view, "#newsletter-error")

      assert html =~
               "This email domain appears to be invalid. Please check your email address."
    end

    test "shows subscription widget for logged-in users", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/newsletters")
      html = render_async(view)

      assert html =~ "subscribed" or html =~ "not subscribed"
    end

    test "reflects subscriber status when user is already subscribed", %{
      conn: conn
    } do
      user = user_fixture()

      assert {:ok, _} =
               Newsletter.subscribe(user.email,
                 user_id: user.id,
                 first_name: user.first_name,
                 last_name: user.last_name,
                 source: "test"
               )

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/newsletters")
      html = render_async(view)

      assert html =~ "subscribed"
      assert has_element?(view, "button", "Unsubscribe")
    end

    test "logged-in user can unsubscribe from newsletters page", %{
      conn: conn
    } do
      user = user_fixture()

      assert {:ok, _} =
               Newsletter.subscribe(user.email,
                 user_id: user.id,
                 first_name: user.first_name,
                 last_name: user.last_name,
                 source: "test"
               )

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/newsletters")
      render_async(view)

      html =
        view
        |> element("button", "Unsubscribe")
        |> render_click()

      assert html =~ "not subscribed" or html =~ "You're not subscribed"
      refute Newsletter.get_subscriber_by_email(user.email).subscribed
    end

    test "toggle subscription shows error when subscriber row is missing", %{
      conn: conn
    } do
      user = user_fixture()

      assert {:ok, sub} =
               Newsletter.subscribe(user.email,
                 user_id: user.id,
                 first_name: user.first_name,
                 last_name: user.last_name,
                 source: "test"
               )

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/newsletters")
      render_async(view)

      Repo.delete!(sub)

      html =
        view
        |> element("button", "Unsubscribe")
        |> render_click()

      assert html =~ "info@ysc.org"
    end

    test "logged-in user can subscribe from newsletters page when not subscribed",
         %{
           conn: conn
         } do
      user =
        user_fixture(%{
          email:
            "newsletter_toggle_#{System.unique_integer([:positive])}@example.com"
        })

      _ =
        case Newsletter.get_subscriber_by_email(user.email) do
          nil -> :ok
          sub -> Repo.delete!(sub)
        end

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/newsletters")
      render_async(view)

      html =
        view
        |> element(~s|button[phx-click="toggle_subscription"]|, "Subscribe")
        |> render_click()

      assert html =~ "receive future newsletters" or html =~ "Subscribed"
    end
  end

  describe "show" do
    test "renders edition with archived HTML", %{conn: conn} do
      admin = user_fixture()
      edition = insert_sent_edition(admin, %{"title" => "Full Issue"})

      {:ok, edition} =
        Newsletter.store_archive_html(
          edition,
          "<html><body><p>Body</p></body></html>"
        )

      {:ok, view, _html} = live(conn, ~p"/newsletters/#{edition.id}")
      html = render_async(view)

      assert html =~ "Full Issue"
      assert html =~ "newsletter-frame"
      assert html =~ ~s(sandbox="")
      assert has_element?(view, "#newsletter-frame[sandbox]")
    end

    test "renders placeholder when archived HTML is missing", %{conn: conn} do
      admin = user_fixture()
      edition = insert_sent_edition(admin, %{"title" => "No Archive"})

      {:ok, view, _html} = live(conn, ~p"/newsletters/#{edition.id}")
      html = render_async(view)

      assert html =~ "No Archive"
      assert html =~ "not available"
    end

    test "show page renders loading state before async resolves", %{conn: conn} do
      missing_id = Ecto.ULID.generate()

      {:ok, _view, html} = live(conn, ~p"/newsletters/#{missing_id}")

      assert html =~ "animate-pulse"
    end

    test "redirects to index when edition does not exist", %{conn: conn} do
      missing_id = Ecto.ULID.generate()

      {:ok, view, _html} = live(conn, ~p"/newsletters/#{missing_id}")

      assert_redirect(view, ~p"/newsletters", 5_000)
    end

    test "show page includes print control when archived HTML is present", %{
      conn: conn
    } do
      admin = user_fixture()

      edition =
        insert_sent_edition(admin, %{
          "title" => "Printable Issue",
          "intro_text" => "<p>Hello</p>"
        })

      {:ok, edition} =
        Newsletter.store_archive_html(
          edition,
          "<html><body><p>Full</p></body></html>"
        )

      {:ok, view, _html} = live(conn, ~p"/newsletters/#{edition.id}")
      html = render_async(view)

      assert has_element?(view, "button", "Save as PDF")
      assert html =~ "newsletter-frame"
    end
  end
end
