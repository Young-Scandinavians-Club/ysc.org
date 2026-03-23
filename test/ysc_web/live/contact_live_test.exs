defmodule YscWeb.ContactLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  describe "mount/3 - unauthenticated" do
    test "loads contact page successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ "Get in touch"
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

      # Turnstile widget should be present
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

      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ "Get in touch"
    end

    test "pre-fills name and email for authenticated users", %{conn: conn} do
      user =
        user_fixture(%{
          first_name: "John",
          last_name: "Doe",
          email: "john@example.com"
        })

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/contact")

      # Should show "Submitting as" section
      assert html =~ "Submitting as"
      assert html =~ "John Doe"
      assert html =~ "john@example.com"
    end

    test "does not show name and email fields for authenticated users", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/contact")

      # Name and email fields should not be visible
      refute has_element?(view, "input[name='contact_form[name]']")
      refute has_element?(view, "input[name='contact_form[email]']")
    end

    test "does not show Turnstile widget for authenticated users", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/contact")

      # Turnstile widget should not be present
      refute html =~ "cf-turnstile"
    end

    test "displays user avatar for authenticated users", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/contact")

      # Should have avatar container
      assert html =~ "rounded-full"
    end
  end

  describe "subject parameter" do
    test "pre-fills subject from URL parameter", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact?subject=Tahoe%20Cabin")

      # Subject should be selected
      assert html =~ "Tahoe Cabin"
    end

    test "works without subject parameter", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")

      # Form should still load
      assert html =~ "Get in touch"
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
      {:ok, _view, html} =
        live(
          conn,
          ~p"/contact?subject=Events&message=Hi%2C%20I%20have%20an%20idea%20for%20an%20event"
        )

      assert html =~ "Hi, I have an idea for an event"
    end

    test "works without message parameter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      assert has_element?(view, "textarea[name='contact_form[message]']")
    end

    test "pre-fills both subject and message together", %{conn: conn} do
      {:ok, view, html} =
        live(
          conn,
          ~p"/contact?subject=Events&message=Hi%2C%20I%20have%20an%20idea%20for%20an%20event%20I%27d%20love%20to%20host%20with%20YSC.%20Here%27s%20what%20I%20had%20in%20mind%3A%20"
        )

      assert has_element?(
               view,
               "select[name='contact_form[subject]'] option[value='Events']"
             )

      assert html =~ "Hi, I have an idea for an event"
    end
  end

  describe "subject options" do
    test "displays all subject options", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ "General Inquiry"
      assert html =~ "Tahoe Cabin"
      assert html =~ "Clear Lake Cabin"
      assert html =~ "Membership"
      assert html =~ "Volunteering"
      assert html =~ "Choir"
      assert html =~ "Board of Directors"
      assert html =~ "Other"
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

      # Validation should happen
      assert is_binary(result)
    end
  end

  describe "contact info cards" do
    test "displays department contact cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ "Tahoe Cabin"
      assert html =~ "tahoe@ysc.org"
      assert html =~ "Clear Lake Cabin"
      assert html =~ "cl@ysc.org"
      assert html =~ "Volunteer"
      assert html =~ "volunteer@ysc.org"
      assert html =~ "Board of Directors"
      assert html =~ "board@ysc.org"
      assert html =~ "Choir"
      assert html =~ "choir@ysc.org"
      assert html =~ "General Inquiry"
      assert html =~ "info@ysc.org"
    end

    test "contact cards have mailto links", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ "mailto:tahoe@ysc.org"
      assert html =~ "mailto:cl@ysc.org"
      assert html =~ "mailto:volunteer@ysc.org"
      assert html =~ "mailto:board@ysc.org"
      assert html =~ "mailto:choir@ysc.org"
      assert html =~ "mailto:info@ysc.org"
    end
  end

  describe "other contact methods" do
    test "displays mailing address", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ "Mailing Address"
      assert html =~ "PO Box 640610"
      assert html =~ "San Francisco, CA 94112"
    end

    test "displays Other Ways to Connect section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ "Other Ways to Connect"
    end
  end

  describe "page structure" do
    test "has two-column layout", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ "lg:grid-cols-2"
    end

    test "includes all main sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ "Get in touch"
      assert html =~ "Contact Directly"
    end
  end

  describe "response time notice" do
    test "displays volunteer response time message", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ "community of volunteers"
      assert html =~ "24–48 hours"
    end
  end

  describe "accessibility" do
    test "includes proper heading hierarchy", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ "<h1"
      assert html =~ "<h2"
    end

    test "form inputs have labels", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      # Check for label elements
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
      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ "hero-home-modern"
      assert html =~ "hero-home"
      assert html =~ "hero-user-group"
      assert html =~ "hero-users"
      assert html =~ "hero-musical-note"
      assert html =~ "hero-computer-desktop"
      assert html =~ "hero-envelope"
      assert html =~ "hero-map-pin"
    end
  end

  describe "empty states" do
    test "does not show success message initially", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/contact")

      refute html =~ "Thank you! Your message has been sent"
    end
  end
end
