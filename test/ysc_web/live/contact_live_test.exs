defmodule YscWeb.ContactLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  describe "mount/3 - unauthenticated" do
    test "loads contact page successfully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "h1", "Get in touch")
    end

    test "sets page title to Contact", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert page_title(view) =~ "Contact"
    end

    test "displays contact form with all fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "#contact-form")
      assert has_element?(view, "input[name='contact_form[name]']")
      assert has_element?(view, "input[name='contact_form[email]']")
      assert has_element?(view, "select[name='contact_form[subject]']")
      assert has_element?(view, "textarea[name='contact_form[message]']")
    end

    test "displays Turnstile widget for unauthenticated users", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ "Turnstile"
    end

    test "shows submit button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "button[type='submit']", "Send Message")
    end
  end

  describe "mount/3 - authenticated" do
    test "loads contact page for authenticated users", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "h1", "Get in touch")
    end

    test "pre-fills name and email for authenticated users", %{conn: conn} do
      user =
        user_fixture(%{
          first_name: "John",
          last_name: "Doe",
          email: "john@example.com"
        })

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "p", "Submitting as")
      assert has_element?(view, "p", "John Doe")
      assert has_element?(view, "p", "john@example.com")
    end

    test "does not show name and email fields for authenticated users", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/contact")

      refute has_element?(view, "input[name='contact_form[name]']")
      refute has_element?(view, "input[name='contact_form[email]']")
    end

    test "does not show Turnstile widget for authenticated users", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/contact")

      refute has_element?(view, ".cf-turnstile")
    end

    test "displays user avatar for authenticated users", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, ".rounded-full")
    end
  end

  describe "subject parameter" do
    test "pre-fills subject from URL parameter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact?subject=Tahoe%20Cabin")

      assert has_element?(
               view,
               "select[name='contact_form[subject]'] option[value='Tahoe Cabin']"
             )
    end

    test "works without subject parameter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "h1", "Get in touch")
    end

    test "pre-fills subject=Events from URL parameter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact?subject=Events")

      assert has_element?(
               view,
               "select[name='contact_form[subject]'] option[value='Events']"
             )
    end
  end

  describe "message parameter" do
    test "pre-fills message from URL parameter", %{conn: conn} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/contact?subject=Events&message=Hi%2C%20I%20have%20an%20idea%20for%20an%20event"
        )

      assert has_element?(
               view,
               "textarea[name='contact_form[message]']",
               "Hi, I have an idea for an event"
             )
    end

    test "works without message parameter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "textarea[name='contact_form[message]']")
    end

    test "pre-fills both subject and message together", %{conn: conn} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/contact?subject=Events&message=Hi%2C%20I%20have%20an%20idea%20for%20an%20event%20I%27d%20love%20to%20host%20with%20YSC.%20Here%27s%20what%20I%20had%20in%20mind%3A%20"
        )

      assert has_element?(
               view,
               "select[name='contact_form[subject]'] option[value='Events']"
             )

      assert has_element?(
               view,
               "textarea[name='contact_form[message]']",
               "Hi, I have an idea for an event"
             )
    end
  end

  describe "subject options" do
    test "displays all subject options", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      for subject <- [
            "General Inquiry",
            "Tahoe Cabin",
            "Clear Lake Cabin",
            "Membership",
            "Volunteering",
            "Choir",
            "Board of Directors",
            "Other"
          ] do
        assert has_element?(
                 view,
                 "select[name='contact_form[subject]'] option[value='#{subject}']"
               )
      end
    end
  end

  describe "save (authenticated)" do
    test "submits contact form without Turnstile when logged in", %{conn: conn} do
      user =
        user_fixture(%{
          first_name: "Contact",
          last_name: "Tester",
          email: "contact_tester#{System.unique_integer()}@example.com"
        })

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/contact")

      view
      |> form("#contact-form",
        contact_form: %{
          subject: "General Inquiry",
          message: "Hello from LiveView test message body."
        }
      )
      |> render_submit()

      assert render(view) =~ "Thank you! Your message has been sent"
    end

    test "keeps form visible when validation fails for logged-in user", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/contact")

      view
      |> form("#contact-form",
        contact_form: %{
          subject: "General Inquiry",
          message: "short"
        }
      )
      |> render_submit()

      assert has_element?(view, "#contact-form")

      refute has_element?(
               view,
               "span",
               "Thank you! Your message has been sent"
             )
    end
  end

  describe "form validation" do
    test "validates form on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      result =
        view
        |> form("#contact-form", contact_form: %{message: "Test message"})
        |> render_change()

      assert result =~ "contact-form"
    end

    test "shows validation errors for invalid data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      result =
        view
        |> form("#contact-form",
          contact_form: %{
            name: "",
            email: "invalid-email",
            subject: "General Inquiry",
            message: ""
          }
        )
        |> render_change()

      assert is_binary(result)
    end
  end

  describe "contact info cards" do
    test "displays department contact cards", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "a[href='mailto:tahoe@ysc.org']", "Tahoe Cabin")

      assert has_element?(
               view,
               "a[href='mailto:tahoe@ysc.org']",
               "tahoe@ysc.org"
             )

      assert has_element?(
               view,
               "a[href='mailto:cl@ysc.org']",
               "Clear Lake Cabin"
             )

      assert has_element?(view, "a[href='mailto:cl@ysc.org']", "cl@ysc.org")

      assert has_element?(
               view,
               "a[href='mailto:volunteer@ysc.org']",
               "Volunteer"
             )

      assert has_element?(
               view,
               "a[href='mailto:volunteer@ysc.org']",
               "volunteer@ysc.org"
             )

      assert has_element?(
               view,
               "a[href='mailto:board@ysc.org']",
               "Board of Directors"
             )

      assert has_element?(
               view,
               "a[href='mailto:board@ysc.org']",
               "board@ysc.org"
             )

      assert has_element?(view, "a[href='mailto:choir@ysc.org']", "Choir")

      assert has_element?(
               view,
               "a[href='mailto:choir@ysc.org']",
               "choir@ysc.org"
             )

      assert has_element?(
               view,
               "a[href='mailto:info@ysc.org']",
               "General Inquiry"
             )

      assert has_element?(view, "a[href='mailto:info@ysc.org']", "info@ysc.org")
    end

    test "contact cards have mailto links", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "a[href='mailto:tahoe@ysc.org']")
      assert has_element?(view, "a[href='mailto:cl@ysc.org']")
      assert has_element?(view, "a[href='mailto:volunteer@ysc.org']")
      assert has_element?(view, "a[href='mailto:board@ysc.org']")
      assert has_element?(view, "a[href='mailto:choir@ysc.org']")
      assert has_element?(view, "a[href='mailto:info@ysc.org']")
    end
  end

  describe "other contact methods" do
    test "displays mailing address", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "p", "Mailing Address")
      assert has_element?(view, "p", "PO Box 640610")
      assert has_element?(view, "p", "San Francisco, CA 94112")
    end

    test "displays Other Ways to Connect section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "h2", "Other Ways to Connect")
    end
  end

  describe "page structure" do
    test "has two-column layout", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ "lg:grid-cols-2"
    end

    test "includes all main sections", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "h1", "Get in touch")
      assert has_element?(view, "h2", "Contact Directly")
    end
  end

  describe "response time notice" do
    test "displays volunteer response time message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "p", "community of volunteers")
      assert has_element?(view, "p", "24–48 hours")
    end
  end

  describe "accessibility" do
    test "includes proper heading hierarchy", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "h1")
      assert has_element?(view, "h2")
    end

    test "form inputs have labels", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "label")
    end

    test "submit button has descriptive text", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "button", "Send Message")
    end
  end

  describe "responsive design" do
    test "includes responsive grid classes", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ "sm:grid-cols-2"
      assert html =~ "lg:grid-cols-2"
    end

    test "includes responsive spacing", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ "lg:py-"
    end
  end

  describe "icons" do
    test "displays icons for contact methods", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(
               view,
               "a[href='mailto:tahoe@ysc.org'] .hero-home-modern"
             )

      assert has_element?(view, "a[href='mailto:cl@ysc.org'] .hero-home")

      assert has_element?(
               view,
               "a[href='mailto:volunteer@ysc.org'] .hero-user-group"
             )

      assert has_element?(view, "a[href='mailto:board@ysc.org'] .hero-users")

      assert has_element?(
               view,
               "a[href='mailto:choir@ysc.org'] .hero-musical-note"
             )

      assert has_element?(
               view,
               "a[href='mailto:web@ysc.org'] .hero-computer-desktop"
             )

      assert has_element?(view, "a[href='mailto:info@ysc.org'] .hero-envelope")
      assert has_element?(view, ".hero-map-pin")
    end
  end

  describe "empty states" do
    test "does not show success message initially", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      refute has_element?(view, "span", "Thank you! Your message has been sent")
    end
  end
end
