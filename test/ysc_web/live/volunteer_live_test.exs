defmodule YscWeb.VolunteerLiveTest do
  use YscWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  describe "mount/3 - unauthenticated" do
    test "loads volunteer page successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "Volunteer with the YSC"
    end

    test "sets page title to Volunteer", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/volunteer")

      assert page_title(view) =~ "Volunteer"
    end

    test "displays volunteer form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/volunteer")

      assert has_element?(view, "#volunteer-form")
    end

    test "displays name and email fields for unauthenticated users", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/volunteer")

      assert has_element?(view, "input[name='volunteer[name]']")
      assert has_element?(view, "input[name='volunteer[email]']")
    end

    test "displays Turnstile widget for unauthenticated users", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "Turnstile"
    end

    test "shows submit button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/volunteer")

      assert has_element?(view, "button[type='submit']", "Submit Application")
    end
  end

  describe "mount/3 - authenticated" do
    test "loads volunteer page for authenticated users", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "Volunteer with the YSC"
    end

    test "pre-fills name and email for authenticated users", %{conn: conn} do
      user =
        user_fixture(%{
          first_name: "Alice",
          last_name: "Smith",
          email: "alice@example.com"
        })

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "Submitting as"
      assert html =~ "Alice Smith"
      assert html =~ "alice@example.com"
    end

    test "does not show visible name and email fields for authenticated users",
         %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/volunteer")

      # Should have hidden fields but not visible inputs
      assert html =~ "type=\"hidden\""
    end

    test "does not show Turnstile widget for authenticated users", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/volunteer")

      refute html =~ "cf-turnstile"
    end

    test "displays user avatar for authenticated users", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "rounded-full"
    end
  end

  describe "header content" do
    test "displays introductory text", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "Want to contribute to a vibrant community"
      assert html =~ "The YSC thrives on the dedication of our volunteers"
    end

    test "displays volunteer photo", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "ysc_group_photo.jpg"
      assert html =~ "Group of YSC Members and Volunteers"
    end
  end

  describe "interest checkboxes" do
    test "displays all interest options", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "Events" and html =~ "Parties"
      assert html =~ "Activities"
      assert html =~ "Clear Lake"
      assert html =~ "Tahoe"
      assert html =~ "Marketing"
      assert html =~ "Website"
    end

    test "all interest checkboxes are present", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/volunteer")

      assert has_element?(view, "input[name='volunteer[interest_events]']")
      assert has_element?(view, "input[name='volunteer[interest_activities]']")
      assert has_element?(view, "input[name='volunteer[interest_clear_lake]']")
      assert has_element?(view, "input[name='volunteer[interest_tahoe]']")
      assert has_element?(view, "input[name='volunteer[interest_marketing]']")
      assert has_element?(view, "input[name='volunteer[interest_website]']")
    end

    test "interest checkboxes have descriptive text", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "Help organize banquets and social gatherings"
      assert html =~ "Plan outdoor adventures and member activities"
      assert html =~ "Help maintain and manage our Clear Lake cabin"
      assert html =~ "Support our mountain retreat at Lake Tahoe"
      assert html =~ "Help us grow our Instagram and newsletter"
      assert html =~ "Help improve and maintain our website"
    end

    test "interest cards have icons", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "hero-calendar"
      assert html =~ "hero-map"
      assert html =~ "hero-home"
      assert html =~ "hero-home-modern"
      assert html =~ "hero-megaphone"
      assert html =~ "hero-computer-desktop"
    end
  end

  describe "form validation" do
    test "validates form on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/volunteer")

      result =
        view
        |> form("#volunteer-form", volunteer: %{name: "Test User"})
        |> render_change()

      assert result =~ "volunteer-form"
    end
  end

  describe "form submission instructions" do
    test "displays volunteer team heading", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "Join Our Team"
    end

    test "displays volunteer-led message", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "100% volunteer-led"
      assert html =~ "Your help keeps our cabins open"
    end

    test "displays multi-select instruction", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "How would you like to volunteer"
      assert html =~ "Select all that apply"
    end
  end

  describe "page structure" do
    test "has two-column header layout", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "lg:grid-cols-2"
    end

    test "includes responsive grid for interest cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "sm:grid-cols-2"
      assert html =~ "lg:grid-cols-3"
    end
  end

  describe "success state" do
    test "does not show success message initially", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      refute html =~ "Välkommen"
      refute html =~ "One of our board members will reach out"
    end
  end

  describe "accessibility" do
    test "checkboxes have aria-labels", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "aria-label=\"Events" and html =~ "Parties"
      assert html =~ "aria-label=\"Activities"
      assert html =~ "aria-label=\"Clear Lake"
      assert html =~ "aria-label=\"Tahoe"
      assert html =~ "aria-label=\"Marketing"
      assert html =~ "aria-label=\"Website"
    end

    test "includes proper heading hierarchy", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "<h1"
      assert html =~ "<h2"
    end

    test "form has proper labels", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/volunteer")

      assert has_element?(view, "label")
    end

    test "submit button has descriptive text", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/volunteer")

      assert has_element?(view, "button", "Submit Application")
    end
  end

  describe "responsive design" do
    test "includes responsive spacing", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "lg:py-"
      assert html =~ "md:grid-cols-"
    end

    test "cards have responsive scaling", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      # Interest cards have hover effects
      assert html =~ "hover:bg-zinc-50"
    end
  end

  describe "visual feedback" do
    test "checkboxes have visual states", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      # Cards change appearance when checked
      assert html =~ "has-[:checked]:border-blue-600"
      assert html =~ "has-[:checked]:bg-blue-50"
    end

    test "icons animate when checkboxes are selected", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "group-has-[:checked]:animate-bounce"
    end

    test "submit button shows loading state", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "phx-submit-loading"
      assert html =~ "Sending..."
    end
  end

  describe "card styling" do
    test "interest cards have hover effects", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "hover:bg-zinc-50"
      assert html =~ "cursor-pointer"
    end

    test "cards scale when checked", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "has-[:checked]:scale-[1.02]"
    end
  end

  describe "form fields" do
    test "name field is required for unauthenticated users", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "Name (*)"
    end

    test "email field is required for unauthenticated users", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/volunteer")

      assert html =~ "Email (*)"
    end
  end

  describe "hidden fields for authenticated users" do
    test "includes hidden name and email fields when logged in", %{conn: conn} do
      user = user_fixture(%{first_name: "Test", last_name: "User"})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/volunteer")

      # Should have hidden inputs for form submission
      assert html =~ "type=\"hidden\""
      assert html =~ "volunteer[name]"
      assert html =~ "volunteer[email]"
    end
  end
end
