defmodule YscWeb.AdminUserDetailsLiveTest do
  use YscWeb.ConnCase

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Repo
  alias Ysc.Subscriptions

  setup :register_and_log_in_admin

  describe "mount" do
    test "loads user details for viewing", %{conn: conn} do
      user = user_fixture(%{first_name: "John", last_name: "Doe"})

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "John"
      assert html =~ "Doe"
    end

    test "displays user avatar", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert has_element?(view, "[class*='w-24 h-24 rounded-full']")
    end

    test "displays back button", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Back"
    end

    test "capitalizes user name", %{conn: conn} do
      user = user_fixture(%{first_name: "jane", last_name: "smith"})

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Jane"
      assert html =~ "Smith"
    end
  end

  describe "navigation tabs" do
    test "displays profile tab", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Profile"
    end

    test "displays tickets tab", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Tickets"
    end

    test "displays bookings tab", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Bookings"
    end

    test "displays application tab", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Application"
    end

    test "profile tab is active by default", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert has_element?(
               view,
               "#user-detail-tabs a.border-blue-500",
               "Profile"
             )
    end

    test "can navigate to orders tab", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      {:ok, _view, orders_html} =
        view
        |> element("a[href$='/details/orders']")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/users/#{user.id}/details/orders")

      assert orders_html =~ "Tickets"
    end

    test "can navigate to bookings tab", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      {:ok, _view, bookings_html} =
        view
        |> element("a[href$='/details/bookings']")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/users/#{user.id}/details/bookings")

      assert bookings_html =~ "Bookings"
    end

    test "can navigate to application tab", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      {:ok, _view, application_html} =
        view
        |> element("a[href$='/details/application']")
        |> render_click()
        |> follow_redirect(
          conn,
          ~p"/admin/users/#{user.id}/details/application"
        )

      assert application_html =~ "Application"
    end
  end

  describe "tab highlighting" do
    test "highlights active tab with correct styles", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "border-blue-500 text-blue-600 bg-white"
    end

    test "non-active tabs have hover styles", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "hover:text-zinc-700 hover:border-zinc-300"
    end
  end

  describe "back navigation" do
    test "back button links to users list", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert view
             |> element("a", "Back")
             |> render()
             |> then(&(&1 =~ "/admin/users"))
    end
  end

  describe "user avatar" do
    test "displays user avatar with email", %{conn: conn} do
      user = user_fixture(%{email: "test@example.com"})

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      # Avatar component should be rendered
      assert has_element?(view, "[class*='rounded-full']")
    end

    test "displays avatar with correct size", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "w-24 h-24"
    end
  end

  describe "page title" do
    test "displays user name as page title", %{conn: conn} do
      user = user_fixture(%{first_name: "Alice", last_name: "Johnson"})

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert html =~ "Alice Johnson"
      assert html =~ "text-2xl font-semibold"
    end
  end

  describe "layout" do
    test "uses admin app layout", %{conn: conn} do
      user = user_fixture()

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user.id}/details")

      # Should have admin layout elements
      assert html =~ "YSC.org Admin"
    end

    test "displays current user info in navigation", %{
      conn: conn,
      user: admin_user
    } do
      viewed_user = user_fixture()

      {:ok, _view, html} =
        live(conn, ~p"/admin/users/#{viewed_user.id}/details")

      # Admin user info should be displayed
      assert html =~ admin_user.email
    end
  end

  describe "membership tab - create paid membership" do
    test "shows create membership (paid elsewhere) form when user has no subscription and no lifetime",
         %{conn: conn} do
      user = user_fixture()
      # Ensure no lifetime
      user = Repo.get!(Ysc.Accounts.User, user.id)
      assert is_nil(Subscriptions.get_active_subscription(user))

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      {:ok, view, html} =
        view
        |> element("a[href$='/details/membership']")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/users/#{user.id}/details/membership")

      assert html =~ "Create membership (paid elsewhere)"
      assert html =~ "create-paid-membership-form"
      assert has_element?(view, "#create-paid-membership-form")
      assert html =~ "Create membership (paid elsewhere)"
    end

    test "does not show create paid membership form when user has active subscription",
         %{conn: conn} do
      user = user_fixture()
      membership_plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(membership_plans, &(&1.id == :single))

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 365, :day)
        })

      if single_plan do
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_price_id: single_plan.stripe_price_id,
          stripe_product_id: "prod_1",
          stripe_id: "si_#{System.unique_integer()}",
          quantity: 1
        })
      end

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      {:ok, _view, html} =
        view
        |> element("a[href$='/details/membership']")
        |> render_click()
        |> follow_redirect(conn, ~p"/admin/users/#{user.id}/details/membership")

      refute html =~ "Create membership (paid elsewhere)"
      assert html =~ "Current Membership"
    end

    test "does not show create paid membership form when user has lifetime membership",
         %{conn: conn} do
      user =
        user_fixture()
        |> Ysc.Accounts.User.update_user_changeset(%{
          lifetime_membership_awarded_at: DateTime.utc_now()
        })
        |> Repo.update!()

      {:ok, _view, html} =
        live(conn, ~p"/admin/users/#{user.id}/details/membership")

      refute html =~ "Create membership (paid elsewhere)"
      assert html =~ "Lifetime Membership"
    end

    test "submitting create paid membership creates subscription and updates UI",
         %{conn: conn} do
      user = user_fixture()
      membership_plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(membership_plans, &(&1.id == :single))
      assert single_plan != nil

      now_unix = System.system_time(:second)
      fake_stripe_sub = build_fake_stripe_subscription(single_plan, now_unix)
      callback = fn _user, _plan -> {:ok, fake_stripe_sub} end

      try do
        Application.put_env(
          :ysc,
          :create_subscription_paid_out_of_band_stripe_callback,
          callback
        )

        {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

        {:ok, view, _html} =
          view
          |> element("a[href$='/details/membership']")
          |> render_click()
          |> follow_redirect(
            conn,
            ~p"/admin/users/#{user.id}/details/membership"
          )

        assert has_element?(view, "#create-paid-membership-form")

        view
        |> form("#create-paid-membership-form", %{
          "create_paid_membership" => %{"plan_id" => "single"}
        })
        |> render_submit()

        assert render(view) =~ "Membership subscription created"
        assert render(view) =~ "Current Membership"
        assert render(view) =~ single_plan.name
      after
        Application.delete_env(
          :ysc,
          :create_subscription_paid_out_of_band_stripe_callback
        )
      end
    end

    test "shows error when create paid membership fails (callback returns error)",
         %{conn: conn} do
      user = user_fixture()
      callback = fn _user, _plan -> {:error, :stripe_api_error} end

      try do
        Application.put_env(
          :ysc,
          :create_subscription_paid_out_of_band_stripe_callback,
          callback
        )

        {:ok, view, _html} =
          live(conn, ~p"/admin/users/#{user.id}/details/membership")

        view
        |> form("#create-paid-membership-form", %{
          "create_paid_membership" => %{"plan_id" => "single"}
        })
        |> render_submit()

        assert render(view) =~ "Failed to create subscription"
      after
        Application.delete_env(
          :ysc,
          :create_subscription_paid_out_of_band_stripe_callback
        )
      end
    end
  end

  defp build_fake_stripe_subscription(plan, now_unix) do
    period_end = now_unix + 365 * 24 * 60 * 60

    %Stripe.Subscription{
      id: "sub_fake_#{System.unique_integer()}",
      status: "active",
      start_date: now_unix,
      current_period_start: now_unix,
      current_period_end: period_end,
      trial_end: nil,
      ended_at: nil,
      items: %Stripe.List{
        data: [
          %{
            id: "si_fake_#{System.unique_integer()}",
            price: %{id: plan.stripe_price_id, product: "prod_fake"},
            quantity: 1
          }
        ],
        has_more: false,
        object: "list",
        url: "/v1/subscription_items"
      }
    }
  end

  describe "impersonation" do
    test "displays Sign in as User button linking to impersonate URL", %{
      conn: conn
    } do
      target = user_fixture(%{first_name: "Alice", last_name: "Target"})

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{target.id}/details")

      assert has_element?(
               view,
               "form#admin-impersonate-form[action='/admin/impersonate/#{target.id}']"
             )

      assert has_element?(
               view,
               "#admin-impersonate-form button",
               "Sign in as User"
             )
    end

    test "Sign in as User button is not shown to non-admin", %{conn: conn} do
      member = user_fixture(%{role: "member"})
      target = user_fixture()
      conn = log_in_user(conn, member)

      # Member cannot access admin user details; they get redirected
      conn = get(conn, ~p"/admin/users/#{target.id}/details")
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "profile form - save fields with incomplete billing address" do
    test "admin can change role when user has no billing address", %{conn: conn} do
      user = user_fixture(%{role: :member})

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert has_element?(view, "#user-profile-form")

      view
      |> form("#user-profile-form", %{
        "user" => %{
          "role" => "admin",
          "billing_address" => %{
            "address" => "",
            "city" => "",
            "region" => "",
            "postal_code" => "",
            "country" => ""
          }
        }
      })
      |> render_submit()

      updated = Ysc.Repo.get!(Ysc.Accounts.User, user.id)
      assert updated.role == :admin
    end

    test "admin can change state when user has no billing address", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      view
      |> form("#user-profile-form", %{
        "user" => %{
          "state" => "suspended",
          "billing_address" => %{
            "address" => "",
            "city" => "",
            "region" => "",
            "postal_code" => "",
            "country" => ""
          }
        }
      })
      |> render_submit()

      updated = Ysc.Repo.get!(Ysc.Accounts.User, user.id)
      assert updated.state == :suspended
    end

    test "admin can change first name when user has no billing address", %{
      conn: conn
    } do
      user = user_fixture(%{first_name: "Alice"})

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      view
      |> form("#user-profile-form", %{
        "user" => %{
          "first_name" => "Alicia",
          "billing_address" => %{
            "address" => "",
            "city" => "",
            "region" => "",
            "postal_code" => "",
            "country" => ""
          }
        }
      })
      |> render_submit()

      updated = Ysc.Repo.get!(Ysc.Accounts.User, user.id)
      assert updated.first_name == "Alicia"
    end

    test "admin can set board position and bio on admin user via profile form",
         %{
           conn: conn
         } do
      user = user_fixture(%{role: :admin})

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      assert has_element?(view, "#user-profile-form")

      empty_billing = %{
        "address" => "",
        "city" => "",
        "region" => "",
        "postal_code" => "",
        "country" => ""
      }

      board_bio = "Treasurer bio for the public board page."

      # Board bio is only rendered after a board position is selected (phx-change).
      view
      |> form("#user-profile-form", %{
        "user" => %{
          "role" => "admin",
          "board_position" => "treasurer",
          "billing_address" => empty_billing
        }
      })
      |> render_change()

      assert has_element?(view, "#board_bio")

      view
      |> form("#user-profile-form", %{
        "user" => %{
          "role" => "admin",
          "board_position" => "treasurer",
          "board_bio" => board_bio,
          "billing_address" => empty_billing
        }
      })
      |> render_submit()

      updated = Repo.get!(Ysc.Accounts.User, user.id)
      assert updated.board_position == :treasurer
      assert updated.board_bio == board_bio

      history = Accounts.list_board_position_history(updated)
      assert length(history) == 1
      assert hd(history).position == :treasurer
    end
  end

  describe "rejection override - save intercepted" do
    test "saving active state for a rejected user with a rejected application shows the override modal",
         %{conn: conn, user: admin} do
      user = user_fixture(%{state: :rejected})

      application =
        signup_application_fixture(user, %{
          review_outcome: "rejected",
          reviewed_at: DateTime.utc_now(),
          reviewed_by_user_id: admin.id
        })

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      view
      |> form("#user-profile-form", %{
        "user" => %{
          "state" => "active",
          "billing_address" => %{
            "address" => "",
            "city" => "",
            "region" => "",
            "postal_code" => "",
            "country" => ""
          }
        }
      })
      |> render_submit()

      assert has_element?(view, "#rejection-override-modal")
      assert has_element?(view, "#override-rejection-form")

      updated = Repo.get!(Ysc.Accounts.User, user.id)
      assert updated.state == :rejected

      _ = application
    end

    test "normal save still works for non-rejected users", %{conn: conn} do
      user = user_fixture(%{state: :active})

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      view
      |> form("#user-profile-form", %{
        "user" => %{
          "state" => "suspended",
          "billing_address" => %{
            "address" => "",
            "city" => "",
            "region" => "",
            "postal_code" => "",
            "country" => ""
          }
        }
      })
      |> render_submit()

      updated = Repo.get!(Ysc.Accounts.User, user.id)
      assert updated.state == :suspended
      refute has_element?(view, "#rejection-override-modal")
    end

    test "normal save still works for rejected user without a rejected application",
         %{conn: conn} do
      user = user_fixture(%{state: :rejected})

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      view
      |> form("#user-profile-form", %{
        "user" => %{
          "state" => "active",
          "billing_address" => %{
            "address" => "",
            "city" => "",
            "region" => "",
            "postal_code" => "",
            "country" => ""
          }
        }
      })
      |> render_submit()

      updated = Repo.get!(Ysc.Accounts.User, user.id)
      assert updated.state == :active
      refute has_element?(view, "#rejection-override-modal")
    end
  end

  describe "rejection override - confirm flow" do
    setup %{conn: conn, user: admin} do
      user = user_fixture(%{state: :rejected})

      application =
        signup_application_fixture(user, %{
          review_outcome: "rejected",
          reviewed_at: DateTime.utc_now(),
          reviewed_by_user_id: admin.id
        })

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user.id}/details")

      view
      |> form("#user-profile-form", %{
        "user" => %{
          "state" => "active",
          "billing_address" => %{
            "address" => "",
            "city" => "",
            "region" => "",
            "postal_code" => "",
            "country" => ""
          }
        }
      })
      |> render_submit()

      %{view: view, user: user, admin: admin, application: application}
    end

    test "confirming with a valid note activates the user", %{
      view: view,
      user: user
    } do
      view
      |> form("#override-rejection-form", %{
        "override" => %{
          "note" => "Spoke with the applicant and confirmed eligibility."
        }
      })
      |> render_submit()

      updated = Repo.get!(Ysc.Accounts.User, user.id)
      assert updated.state == :active
    end

    test "confirming with a valid note creates a rejection-category note", %{
      view: view,
      user: user,
      admin: admin
    } do
      view
      |> form("#override-rejection-form", %{
        "override" => %{
          "note" => "Spoke with the applicant and confirmed eligibility."
        }
      })
      |> render_submit()

      notes = Ysc.Accounts.list_user_notes_by_category(user.id, :rejection)
      assert length(notes) == 1
      [note] = notes
      assert note.note == "Spoke with the applicant and confirmed eligibility."
      assert note.created_by_user_id == admin.id
    end

    test "submitting with a blank note shows a validation error and does not save",
         %{view: view, user: user} do
      view
      |> form("#override-rejection-form", %{
        "override" => %{"note" => ""}
      })
      |> render_submit()

      updated = Repo.get!(Ysc.Accounts.User, user.id)
      assert updated.state == :rejected
      assert has_element?(view, "#override-rejection-form")
    end

    test "submitting with a too-short note shows a validation error and does not save",
         %{view: view, user: user} do
      view
      |> form("#override-rejection-form", %{
        "override" => %{"note" => "Short"}
      })
      |> render_submit()

      updated = Repo.get!(Ysc.Accounts.User, user.id)
      assert updated.state == :rejected
      assert has_element?(view, "#override-rejection-form")
    end

    test "cancelling the override dismisses the modal and does not save",
         %{view: view, user: user} do
      render_click(view, "cancel_activation_override")

      updated = Repo.get!(Ysc.Accounts.User, user.id)
      assert updated.state == :rejected
      refute has_element?(view, "#rejection-override-modal")
    end

    test "live validation in the override form updates errors",
         %{view: view} do
      view
      |> form("#override-rejection-form", %{"override" => %{"note" => "Hi"}})
      |> render_change()

      assert has_element?(view, "#override-rejection-form .field-error")
    end
  end

  describe "rejection override - application tab display" do
    test "shows override banner on application tab when rejection was overridden",
         %{conn: conn, user: admin} do
      user = user_fixture(%{state: :active})

      application =
        signup_application_fixture(user, %{
          review_outcome: "rejected",
          reviewed_at: DateTime.utc_now(),
          reviewed_by_user_id: admin.id
        })

      {:ok, _note} =
        Ysc.Accounts.create_user_note(
          user,
          %{
            "note" => "Override reason: eligibility confirmed.",
            "category" => "rejection"
          },
          admin
        )

      {:ok, view, _html} =
        live(conn, ~p"/admin/users/#{user.id}/details/application")

      render_async(view)

      assert has_element?(view, "#admin-application-rejection-override-banner")
      assert has_element?(view, "[data-testid='rejection-note-text']")

      _ = application
    end

    test "does not show override banner for a still-rejected user with rejection notes",
         %{conn: conn, user: admin} do
      user = user_fixture(%{state: :rejected})

      application =
        signup_application_fixture(user, %{
          review_outcome: "rejected",
          reviewed_at: DateTime.utc_now(),
          reviewed_by_user_id: admin.id
        })

      {:ok, _note} =
        Ysc.Accounts.create_user_note(
          user,
          %{
            "note" => "Application did not meet eligibility criteria.",
            "category" => "rejection"
          },
          admin
        )

      {:ok, view, _html} =
        live(conn, ~p"/admin/users/#{user.id}/details/application")

      render_async(view)

      assert has_element?(view, "#admin-application-rejection-notes")
      assert has_element?(view, "[data-testid='rejection-note-text']")
      refute has_element?(view, "#admin-application-rejection-override-banner")

      _ = application
    end

    test "does not show rejection notes section when there are no rejection notes",
         %{conn: conn, user: admin} do
      user = user_fixture(%{state: :rejected})

      application =
        signup_application_fixture(user, %{
          review_outcome: "rejected",
          reviewed_at: DateTime.utc_now(),
          reviewed_by_user_id: admin.id
        })

      {:ok, view, _html} =
        live(conn, ~p"/admin/users/#{user.id}/details/application")

      render_async(view)

      refute has_element?(view, "section", "Rejection notes")

      _ = application
    end
  end

  defp register_and_log_in_admin(%{conn: conn}) do
    user = user_fixture(%{role: :admin})
    %{conn: log_in_user(conn, user), user: user}
  end
end
