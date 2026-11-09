defmodule YscWeb.PageControllerTest do
  use YscWeb.ConnCase
  import Mox
  import Ysc.AccountsFixtures

  # Set up mocks for this test module
  setup :verify_on_exit!

  describe "GET /" do
    test "renders home page", %{conn: conn} do
      conn = get(conn, ~p"/")
      # Check for content that actually exists on the home page
      html = html_response(conn, 200)
      assert html =~ "Young Scandinavians Club"
    end
  end

  describe "GET /history" do
    test "groups the timeline by decade with matching jump links", %{conn: conn} do
      html = conn |> get(~p"/history") |> html_response(200)
      document = LazyHTML.from_fragment(html)

      for decade <- ~w(1950s 1960s 1970s 1980s 1990s 2000s 2010s 2020s) do
        assert Enum.count(LazyHTML.query(document, "section#decade-#{decade}")) ==
                 1

        assert Enum.count(
                 LazyHTML.query(document, "a[href='#decade-#{decade}']")
               ) == 1
      end

      assert Enum.count(LazyHTML.query(document, "section#presidents")) == 1

      assert Enum.count(
               LazyHTML.query(document, "#timeline-filter-organization")
             ) == 1
    end

    test "each decade holds only its own events", %{conn: conn} do
      html = conn |> get(~p"/history") |> html_response(200)
      document = LazyHTML.from_fragment(html)

      count = fn decade ->
        document
        |> LazyHTML.query("section#decade-#{decade} [data-timeline-item]")
        |> Enum.count()
      end

      assert count.("1970s") == 5
      assert count.("1980s") == 6
    end

    test "invite card links to contact with a single-encoded message", %{
      conn: conn
    } do
      html = conn |> get(~p"/history") |> html_response(200)
      refute html =~ "%2520"
      refute html =~ "%2527"

      document = LazyHTML.from_fragment(html)

      [href] =
        document
        |> LazyHTML.query("a[href^='/contact?']")
        |> LazyHTML.attribute("href")

      query = href |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      assert query["subject"] == "Board of Directors"
      assert query["message"] =~ "Hi, I'm interested"
    end

    test "archival photos do not nest figures", %{conn: conn} do
      html = conn |> get(~p"/history") |> html_response(200)
      document = LazyHTML.from_fragment(html)

      assert Enum.empty?(LazyHTML.query(document, "figure.archival-photo"))
      refute Enum.empty?(LazyHTML.query(document, "div.archival-photo"))
    end
  end

  describe "GET /board" do
    test "embeds the public board meeting calendar", %{conn: conn} do
      conn = get(conn, ~p"/board")
      html = html_response(conn, 200)

      iframe =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("iframe#board-meeting-calendar")

      assert Enum.count(iframe) == 1

      assert html =~
               "c_d621b3a4fc0326de60ed10ce25ca45e0c5c818f9947b1ebb4f5a71311f61963c"

      assert html =~ "Board Meeting Schedule"

      assert LazyHTML.from_fragment(html)
             |> LazyHTML.query(
               "#board-meeting-attendance a[href='mailto:board@ysc.org']"
             )
             |> Enum.count() == 1
    end
  end

  describe "GET /choir" do
    test "renders choir photo with WebP sources and JPG fallback", %{
      conn: conn
    } do
      html = conn |> get(~p"/choir") |> html_response(200)
      document = LazyHTML.from_fragment(html)

      assert Enum.count(
               LazyHTML.query(
                 document,
                 "picture source[type='image/webp'][srcset*='choir-480.webp']"
               )
             ) == 1

      assert Enum.count(
               LazyHTML.query(
                 document,
                 "picture img#choir-photo[src*='choir.jpg']"
               )
             ) == 1

      assert Enum.empty?(
               LazyHTML.query(document, "img#choir-photo[srcset*='.webp']")
             )
    end

    test "renders choir leader by name when no matching user exists", %{
      conn: conn
    } do
      conn = get(conn, ~p"/choir")

      html = html_response(conn, 200)
      assert html =~ "The choir is led by our board member"
      assert html =~ "Christoffer Tevrén"
      assert conn.assigns.choir_leader == nil
    end

    test "renders choir leader user card when matching user exists", %{
      conn: conn
    } do
      user_fixture(%{
        email: "chrtev@gmail.com",
        first_name: "Christoffer",
        last_name: "Tevrén"
      })

      conn = get(conn, ~p"/choir")

      html = html_response(conn, 200)
      assert html =~ "Choir Leader"
      assert html =~ "Christoffer Tevrén"
      assert html =~ ~s(alt="User avatar")
      assert conn.assigns.choir_leader.email == "chrtev@gmail.com"
    end
  end

  describe "GET /pending-review" do
    setup %{conn: conn} do
      user = user_fixture(%{country: "SE", state: :pending_approval})
      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "redirects active users with membership to the home page", %{
      conn: conn
    } do
      active_user = user_fixture(%{country: "SE", state: :active})

      {:ok, _sub} =
        Ysc.Subscriptions.create_subscription(%{
          name: "Test Membership",
          stripe_id: "sub_pending_review_#{System.unique_integer([:positive])}",
          stripe_status: "active",
          user_id: active_user.id,
          current_period_end: DateTime.add(DateTime.utc_now(), 365, :day)
        })

      _ = Ysc.Accounts.MembershipCache.invalidate_user(active_user.id)

      conn = conn |> log_in_user(active_user) |> get(~p"/pending-review")

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects unpaid active users to account setup payment step", %{
      conn: conn
    } do
      active_user = user_fixture(%{country: "SE", state: :active})
      conn = conn |> log_in_user(active_user) |> get(~p"/pending-review")

      assert redirected_to(conn) ==
               ~p"/account/setup/#{active_user.id}?step=1"
    end

    test "redirects rejected users to login when session is invalid", %{
      conn: conn
    } do
      rejected_user = user_fixture(%{country: "SE", state: :rejected})
      conn = conn |> log_in_user(rejected_user) |> get(~p"/pending-review")

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "redirects suspended users to login when session is invalid", %{
      conn: conn
    } do
      suspended_user = user_fixture(%{country: "SE", state: :suspended})
      conn = conn |> log_in_user(suspended_user) |> get(~p"/pending-review")

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "redirects deleted users to login when session is invalid", %{
      conn: conn
    } do
      deleted_user = user_fixture(%{country: "SE", state: :deleted})
      conn = conn |> log_in_user(deleted_user) |> get(~p"/pending-review")

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "renders pending review page with submission from Pacific timezone", %{
      conn: conn,
      user: _user
    } do
      submitted_date = DateTime.add(DateTime.utc_now(), -300, :second)
      timezone = "America/Los_Angeles"

      Mox.expect(
        Ysc.AccountsMock,
        :get_signup_application_submission_date,
        fn _user_id ->
          %{submit_date: submitted_date, timezone: timezone}
        end
      )

      conn = get(conn, ~p"/pending-review")

      html = html_response(conn, 200)
      assert html =~ "Application Under Review"
      refute html =~ "Account Pending Review"
      assert html =~ "You haven't saved a payment method yet"
      assert html =~ "Save a payment method"
      assert html =~ "Membership starts:"
      refute html =~ "Continue account setup"
      refute html =~ "Activation:"
      assert conn.assigns.application_submitted_date != nil
      assert conn.assigns.time_delta =~ "ago"
    end

    test "explains a saved payment method when one is on file",
         %{
           conn: conn,
           user: user
         } do
      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{
          stripe_id: "cus_pending_review_#{System.unique_integer([:positive])}"
        })
        |> Ysc.Repo.update()

      {:ok, _pm} =
        Ysc.Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id:
            "pm_pending_review_#{System.unique_integer([:positive])}",
          provider_customer_id: user.stripe_id,
          type: :card,
          provider_type: "card",
          is_default: true
        })

      submitted_date = DateTime.add(DateTime.utc_now(), -300, :second)

      Mox.expect(
        Ysc.AccountsMock,
        :get_signup_application_submission_date,
        fn _user_id ->
          %{submit_date: submitted_date, timezone: "America/Los_Angeles"}
        end
      )

      conn = conn |> log_in_user(user) |> get(~p"/pending-review")
      html = html_response(conn, 200)

      assert html =~ "You've saved a payment method"
      assert html =~ "we'll charge the payment method you saved"
      assert html =~ "Membership starts:"
      refute html =~ "Continue account setup"
      refute html =~ "Activation:"
      refute html =~ "payment method will be charged"
    end

    test "renders pending review page with submission from different timezone",
         %{
           conn: conn,
           user: _user
         } do
      submitted_date = DateTime.add(DateTime.utc_now(), -300, :second)
      timezone = "Europe/Stockholm"

      Mox.expect(
        Ysc.AccountsMock,
        :get_signup_application_submission_date,
        fn _user_id ->
          %{submit_date: submitted_date, timezone: timezone}
        end
      )

      conn = get(conn, ~p"/pending-review")

      assert html_response(conn, 200)
      assert conn.assigns.application_submitted_date != nil
      assert conn.assigns.time_delta =~ "ago"
    end

    test "handles missing timezone by defaulting to America/Los_Angeles", %{
      conn: conn,
      user: _user
    } do
      submitted_date = DateTime.add(DateTime.utc_now(), -300, :second)

      Mox.expect(
        Ysc.AccountsMock,
        :get_signup_application_submission_date,
        fn _user_id ->
          %{submit_date: submitted_date, timezone: nil}
        end
      )

      conn = get(conn, ~p"/pending-review")

      assert html_response(conn, 200)
      assert conn.assigns.application_submitted_date != nil
      assert conn.assigns.time_delta =~ "ago"
    end
  end

  test "requires authentication", %{conn: conn} do
    conn = get(conn, ~p"/pending-review")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  describe "GET /financials" do
    setup :register_and_log_in_user

    test "renders year sections and download cards", %{conn: conn} do
      conn = get(conn, ~p"/financials")
      html = html_response(conn, 200)
      document = LazyHTML.from_fragment(html)

      assert html =~ "Financials &amp; Annual Meetings"

      assert document
             |> LazyHTML.query("#year-2026")
             |> Enum.count() == 1

      assert document
             |> LazyHTML.query("#financials-2026-summary")
             |> Enum.count() == 1

      assert document
             |> LazyHTML.query("#financials-2026-report")
             |> Enum.count() == 1

      assert document
             |> LazyHTML.query("#financials-2018-slides")
             |> Enum.count() == 1

      summary =
        document
        |> LazyHTML.query("a#financials-2026-summary")
        |> LazyHTML.to_html()

      assert summary =~ "Financials Summary 2025"
      assert summary =~ "PDF • 70K"
      assert summary =~ "target=\"_blank\""
      assert summary =~ "YSC_ANNUAL_MEETING_REPORT_FY_2025.pdf"
    end

    test "lists every meeting year and wires archive links to the details", %{
      conn: conn
    } do
      html = conn |> get(~p"/financials") |> html_response(200)
      document = LazyHTML.from_fragment(html)

      for year <- 2018..2026 do
        assert Enum.count(LazyHTML.query(document, "#year-#{year}")) == 1

        assert Enum.count(
                 LazyHTML.query(document, "nav a[href='#year-#{year}']")
               ) == 1
      end

      assert Enum.count(
               LazyHTML.query(document, "details#financials-archive #year-2022")
             ) ==
               1

      archive_links =
        LazyHTML.query(
          document,
          "nav a[data-opens-details='financials-archive']"
        )

      assert Enum.count(archive_links) == 5

      assert Enum.count(LazyHTML.query(document, "#year-2026 a[href$='.pdf']")) ==
               3
    end
  end

  describe "GET /brand" do
    test "is public and shows every section", %{conn: conn} do
      html = conn |> get(~p"/brand") |> html_response(200)
      document = LazyHTML.from_fragment(html)

      assert Enum.count(LazyHTML.query(document, "#brand-masthead")) == 1

      for id <- ~w(logo color type components imagery charts slides) do
        assert Enum.count(LazyHTML.query(document, "section##{id}")) == 1

        assert Enum.count(
                 LazyHTML.query(document, "#brand-nav a[href='##{id}']")
               ) == 1
      end

      assert Enum.count(LazyHTML.query(document, "#country-palette > li")) == 5

      assert Enum.count(LazyHTML.query(document, "#contrast-table tbody tr")) ==
               8
    end

    test "offers each logo in every format", %{conn: conn} do
      html = conn |> get(~p"/brand") |> html_response(200)
      document = LazyHTML.from_fragment(html)

      assert Enum.count(
               LazyHTML.query(document, "a#download-all-logos[download]")
             ) == 1

      variants = YscWeb.BrandGuide.logo_variants()
      assert length(variants) == 5

      for variant <- variants do
        assert Enum.count(LazyHTML.query(document, "#logo-#{variant.slug}")) ==
                 1

        for file <- variant.downloads do
          assert Enum.count(
                   LazyHTML.query(
                     document,
                     "#logo-#{variant.slug} a[download][href='#{file.href}']"
                   )
                 ) == 1
        end

        assert Enum.map(variant.downloads, & &1.label) ==
                 ["SVG", "PNG 2000 px", "PNG 512 px", "PDF", "AI"]
      end
    end

    test "all logo and template files exist and are served", %{conn: conn} do
      static = :code.priv_dir(:ysc) |> Path.join("static")

      files =
        Enum.flat_map(
          YscWeb.BrandGuide.logo_variants(),
          &YscWeb.BrandGuide.logo_files(&1.slug)
        ) ++
          ["images/brand/logos/ysc-logos.zip"] ++
          YscWeb.BrandGuide.template_files() ++
          YscWeb.BrandGuide.document_template_files() ++
          YscWeb.BrandGuide.palette_files() ++
          YscWeb.BrandGuide.social_kit_files()

      assert length(files) > 40

      for file <- files do
        assert File.regular?(Path.join(static, file)), "missing #{file}"
        assert conn |> get("/" <> file) |> response(200)
      end
    end

    test "links to both template downloads", %{conn: conn} do
      html = conn |> get(~p"/brand") |> html_response(200)
      document = LazyHTML.from_fragment(html)

      assert Enum.count(
               LazyHTML.query(document, "a#download-template-potx[download]")
             ) == 1

      assert Enum.count(
               LazyHTML.query(document, "a#download-template-pptx[download]")
             ) == 1
    end

    test "offers document, palette and social kit downloads", %{conn: conn} do
      html = conn |> get(~p"/brand") |> html_response(200)
      document = LazyHTML.from_fragment(html)

      for id <- ~w(documents web checklist) do
        assert Enum.count(LazyHTML.query(document, "section##{id}")) == 1

        assert Enum.count(
                 LazyHTML.query(document, "#brand-nav a[href='##{id}']")
               ) == 1
      end

      for id <-
            ~w(download-document-dotx download-document-docx download-social-kit) do
        assert Enum.count(LazyHTML.query(document, "a##{id}[download]")) == 1
      end

      assert Enum.count(
               LazyHTML.query(document, "#palette-downloads a[download]")
             ) == 4

      assert Enum.count(LazyHTML.query(document, "#post-canvases > li")) == 5

      assert Enum.count(LazyHTML.query(document, "#post-canvases a[download]")) ==
               15

      assert Enum.count(
               LazyHTML.query(document, "#profile-pictures a[download]")
             ) == 3

      assert Enum.count(LazyHTML.query(document, "#image-sizes tbody tr")) == 8

      assert Enum.count(
               LazyHTML.query(
                 document,
                 "button#copy-email-signature[data-copy]"
               )
             ) == 1
    end

    test "hides the Google Slides button until a template is configured", %{
      conn: conn
    } do
      html = conn |> get(~p"/brand") |> html_response(200)
      document = LazyHTML.from_fragment(html)

      assert Enum.empty?(LazyHTML.query(document, "#open-in-google-slides"))
    end

    test "shows a Google Slides copy link when a template is configured", %{
      conn: conn
    } do
      Application.put_env(:ysc, :brand_google_slides_template_id, "abc_123-XYZ")

      on_exit(fn ->
        Application.delete_env(:ysc, :brand_google_slides_template_id)
      end)

      html = conn |> get(~p"/brand") |> html_response(200)
      document = LazyHTML.from_fragment(html)

      assert Enum.count(
               LazyHTML.query(
                 document,
                 "a#open-in-google-slides[href='https://docs.google.com/presentation/d/abc_123-XYZ/copy'][target='_blank']"
               )
             ) == 1
    end
  end
end
