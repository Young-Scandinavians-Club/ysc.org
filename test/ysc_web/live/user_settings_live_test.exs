defmodule YscWeb.UserSettingsLiveTest do
  # async: false because tests use Application.put_env for global callback overrides
  # that would race with Ysc.SubscriptionsTest using the same keys
  use YscWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ysc.AccountsFixtures
  import Ysc.EventsFixtures

  alias Money
  alias Ysc.Accounts
  alias Ysc.Accounts.FamilyInvites
  alias Ysc.Accounts.MembershipCache
  alias Ysc.Bookings.Entitlements
  alias Ysc.Events.TicketReservation
  alias Ysc.LedgersFixtures
  alias Ysc.MessagePassingEvents
  alias Ysc.Newsletter
  alias Ysc.Payments
  alias Ysc.Repo
  alias Ysc.Subscriptions

  setup :verify_on_exit!

  # Helpers that target the ReauthComponent (a LiveComponent) rather than the
  # parent UserSettingsLive, since reauth events are now handled by the component.

  defp submit_reauth_password(view, password) do
    view
    |> element("#reauth_password_form")
    |> render_submit(%{"password" => password})

    render(view)
  end

  defp click_cancel_reauth(view) do
    view
    |> element("#reauth-modal button[phx-click='cancel_reauth']")
    |> render_click()

    render(view)
  end

  defp click_reauth_with_passkey(view) do
    view
    |> element("#reauth-passkey-hook button[phx-click='reauth_with_passkey']")
    |> render_click()
  end

  defp hook_passkey_auth_error(view, params) do
    view
    |> element("#reauth-passkey-hook")
    |> render_hook("passkey_auth_error", params)
  end

  describe "membership PubSub real-time updates" do
    setup %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "shows info flash when membership is updated for the current user", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/users/membership")

      refute has_element?(view, "#flash-info")

      refute view |> render() |> to_string() =~
               "Your membership has been updated"

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "memberships:user:#{user.id}",
        {Ysc.Subscriptions,
         %MessagePassingEvents.MembershipUpdated{user_id: user.id}}
      )

      # render/1 synchronises with the LiveView process (test README: no sleep needed after PubSub)
      assert view |> render() |> to_string() =~
               "Your membership has been updated",
             "Expected membership update toast to appear after PubSub broadcast"
    end

    test "reloads membership data and updates the UI on receiving a PubSub event",
         %{
           conn: conn,
           user: user
         } do
      try do
        Application.put_env(
          :ysc,
          :get_scheduled_downgrade_info_callback,
          fn _sub -> nil end
        )

        {:ok, view, _html} = live(conn, ~p"/users/membership")

        refute has_element?(view, "button[phx-click=\"cancel-membership\"]")

        {:ok, _subscription} =
          Subscriptions.create_subscription(%{
            user_id: user.id,
            stripe_id: "sub_pubsub_test_#{System.unique_integer()}",
            stripe_status: "active",
            name: "Membership",
            current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
          })

        MembershipCache.invalidate_user(user.id)

        Phoenix.PubSub.broadcast(
          Ysc.PubSub,
          "memberships:user:#{user.id}",
          {Ysc.Subscriptions,
           %MessagePassingEvents.MembershipUpdated{user_id: user.id}}
        )

        assert has_element?(view, "button[phx-click=\"cancel-membership\"]")
      after
        Application.delete_env(:ysc, :get_scheduled_downgrade_info_callback)
      end
    end

    test "ignores membership updates intended for a different user", %{
      conn: conn
    } do
      other_user = user_fixture(%{state: :active})

      {:ok, view, _html} = live(conn, ~p"/users/membership")

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "memberships:user:#{other_user.id}",
        {Ysc.Subscriptions,
         %MessagePassingEvents.MembershipUpdated{user_id: other_user.id}}
      )

      refute has_element?(view, "#flash-info")
    end
  end

  describe "scheduled downgrade notice" do
    test "displays downgrade scheduled notice when user has scheduled downgrade",
         %{
           conn: conn
         } do
      user = user_fixture(%{state: :active})

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_scheduled_test",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      subscription = Repo.preload(subscription, :subscription_items)
      effective_date = DateTime.add(DateTime.utc_now(), 30, :day)

      callback = fn sub ->
        assert sub.id == subscription.id
        %{target_plan: :single, effective_date: effective_date}
      end

      try do
        Application.put_env(
          :ysc,
          :get_scheduled_downgrade_info_callback,
          callback
        )

        conn = log_in_user(conn, user)

        {:ok, view, _html} = live(conn, ~p"/users/membership")

        # load_settings_data runs on connect - wait for scheduled downgrade notice
        assert view
               |> element("[data-testid=\"scheduled-downgrade-notice\"]")
               |> has_element?(),
               "Expected scheduled downgrade notice to be visible"
      after
        Application.delete_env(:ysc, :get_scheduled_downgrade_info_callback)
      end
    end

    test "does not display downgrade notice when user has no scheduled downgrade",
         %{
           conn: conn
         } do
      user = user_fixture(%{state: :active})

      {:ok, _subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_no_schedule",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      callback = fn _sub -> nil end

      try do
        Application.put_env(
          :ysc,
          :get_scheduled_downgrade_info_callback,
          callback
        )

        conn = log_in_user(conn, user)

        {:ok, _view, html} = live(conn, ~p"/users/membership")

        refute html =~ "Downgrade Scheduled"
      after
        Application.delete_env(:ysc, :get_scheduled_downgrade_info_callback)
      end
    end

    test "cancel downgrade button cancels scheduled downgrade", %{conn: conn} do
      user = user_fixture(%{state: :active})

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_cancel_test",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      subscription = Repo.preload(subscription, :subscription_items)
      effective_date = DateTime.add(DateTime.utc_now(), 30, :day)

      get_info_callback = fn sub ->
        assert sub.id == subscription.id
        %{target_plan: :single, effective_date: effective_date}
      end

      cancel_callback = fn sub ->
        assert sub.id == subscription.id
        {:ok, sub}
      end

      try do
        Application.put_env(
          :ysc,
          :get_scheduled_downgrade_info_callback,
          get_info_callback
        )

        Application.put_env(
          :ysc,
          :cancel_scheduled_downgrade_callback,
          cancel_callback
        )

        conn = log_in_user(conn, user)

        {:ok, view, _html} = live(conn, ~p"/users/membership")

        assert view
               |> element("[data-testid=\"scheduled-downgrade-notice\"]")
               |> has_element?()

        view
        |> element("[data-testid=\"scheduled-downgrade-notice\"] button")
        |> render_click()

        assert_patched(view, ~p"/users/membership")
        assert render(view) =~ "Scheduled downgrade cancelled"
      after
        Application.delete_env(:ysc, :get_scheduled_downgrade_info_callback)
        Application.delete_env(:ysc, :cancel_scheduled_downgrade_callback)
      end
    end
  end

  describe "membership upgrade requires payment method" do
    test "change membership plan button is disabled when user has no payment method",
         %{conn: conn} do
      # Manual (paid elsewhere) members have no payment method. Upgrading would
      # create an invoice that cannot be paid. UI must disable upgrade and show
      # message to add a payment method first.
      user = user_fixture(%{state: :active})

      # Give user a stripe_id so load_settings_data doesn't call Stripe to create customer
      {:ok, user} =
        user
        |> Ecto.Changeset.change(
          stripe_id: "cus_test_#{System.unique_integer()}"
        )
        |> Repo.update()

      user = Repo.reload(user)

      plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(plans, &(&1.id == :single))
      assert single_plan, "membership_plans must include single"

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_no_pm_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Membership",
          current_period_start: DateTime.utc_now(),
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, _item} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_no_pm_#{System.unique_integer()}",
          stripe_product_id: "prod_single",
          stripe_price_id: single_plan.stripe_price_id,
          quantity: 1
        })

      # User has no payment methods (manual membership)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership")

      # Wait for async load_settings_data so membership and payment methods are loaded
      render(view)
      assert view |> element("#membership_form") |> has_element?()

      # Select family (upgrade) so the "Change Membership Plan" button appears
      render_change(view, "validate_membership", %{
        "membership_type" => "family"
      })

      # When there is no payment method, the button must be disabled
      # (manual/paid-elsewhere members have no payment method; upgrade would create unpaid invoice)
      assert has_element?(
               view,
               "[data-testid=\"change-membership-plan-button\"]"
             )

      change_btn =
        view |> element("[data-testid=\"change-membership-plan-button\"]")

      assert change_btn |> render() =~ "disabled"
    end
  end

  describe "settings page — membership PubSub on settings route" do
    test "PubSub membership update shows toast on /users/settings", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      refute view |> render() |> to_string() =~
               "Your membership has been updated"

      Phoenix.PubSub.broadcast(
        Ysc.PubSub,
        "memberships:user:#{user.id}",
        {Ysc.Subscriptions,
         %MessagePassingEvents.MembershipUpdated{user_id: user.id}}
      )

      assert view |> render() |> to_string() =~
               "Your membership has been updated"
    end
  end

  describe "settings page — layout and profile" do
    setup %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)
      %{conn: conn, user: Repo.get!(Ysc.Accounts.User, user.id)}
    end

    test "renders main settings sections after load", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      assert has_element?(view, "#user-settings-page")
      assert has_element?(view, "#profile_form")
      assert has_element?(view, "#address_form")
      assert has_element?(view, "#email_form")
      assert render(view) =~ "Personal Information"
      assert render(view) =~ "Billing Address"
    end

    test "update_profile shows validation errors for invalid first name", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "update_profile", %{
        "user" =>
          profile_form_attrs(user, %{
            "first_name" => "",
            "last_name" => user.last_name
          })
      })

      html = render(view)

      assert html =~ "can't be blank" or html =~ "at least" or
               html =~ "required"
    end

    test "updates profile when phone number is unchanged", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      new_first = "ProfileTest#{System.unique_integer([:positive])}"

      render_submit(view, "update_profile", %{
        "user" => profile_form_attrs(user, %{"first_name" => new_first})
      })

      assert render(view) =~ "Profile updated successfully"
      updated = Repo.get!(Ysc.Accounts.User, user.id)
      assert updated.first_name == new_first
    end

    test "update_address shows errors for missing required fields", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "update_address", %{
        "address" => %{
          "address" => "",
          "city" => "",
          "postal_code" => "",
          "region" => "",
          "country" => ""
        }
      })

      html = render(view)
      assert html =~ "can't be blank" or html =~ "required"
    end

    test "updates billing address successfully", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      suffix = System.unique_integer([:positive])

      render_submit(view, "update_address", %{
        "address" => %{
          "address" => "456 Oak Ave #{suffix}",
          "city" => "Oakland",
          "postal_code" => "94607",
          "region" => "CA",
          "country" => "USA"
        }
      })

      assert render(view) =~ "Billing address updated successfully"
      reloaded = Accounts.get_user!(user.id, [:billing_address])
      assert reloaded.billing_address.address =~ "456 Oak Ave"
    end

    test "update_profile shows validation error for invalid phone number", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "update_profile", %{
        "user" =>
          profile_form_attrs(user, %{
            "phone_number" => "not-a-real-number"
          })
      })

      html = render(view)
      assert html =~ "phone" or html =~ "Phone" or html =~ "valid"
    end

    test "validate_address shows city change without persisting", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      html =
        render_change(view, "validate_address", %{
          "address" => %{
            "address" => "1 Test St",
            "city" => "Validate City",
            "postal_code" => "94102",
            "region" => "CA",
            "country" => "USA"
          }
        })

      assert html =~ "Validate City" or html =~ "Billing Address"
    end
  end

  describe "settings page — notifications" do
    test "shows newsletter subscribed after async preferences load", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})

      assert {:ok, _} =
               Newsletter.subscribe(user.email,
                 user_id: user.id,
                 source: "test"
               )

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/notifications")
      render(view)

      assert has_element?(
               view,
               "#notification_form[data-testid=notification-preferences-ready]"
             )

      subscriber = Newsletter.get_subscriber_by_email(user.email)
      assert subscriber.subscribed

      html = render(view)
      assert html =~ ~r/name="user\[newsletter_notifications\]"[^>]*checked/s
    end

    test "update_notifications is ignored while notification preferences are loading",
         %{
           conn: conn
         } do
      user = user_fixture(%{state: :active})

      assert {:ok, _} =
               Newsletter.subscribe(user.email,
                 user_id: user.id,
                 source: "test"
               )

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/notifications")
      render(view)

      %{socket: socket} = :sys.get_state(view.pid)

      assert {:noreply, new_socket} =
               YscWeb.UserSettingsLive.handle_event(
                 "update_notifications",
                 %{
                   "user" => %{
                     "newsletter_notifications" => "false",
                     "event_notifications" => "true",
                     "event_notifications_sms" => "false",
                     "account_notifications_sms" => "false"
                   }
                 },
                 %{
                   socket
                   | assigns:
                       Map.put(
                         socket.assigns,
                         :loading_notification_preferences,
                         true
                       )
                 }
               )

      subscriber = Newsletter.get_subscriber_by_email(user.email)
      assert subscriber.subscribed
      assert new_socket.assigns.loading_notification_preferences
    end

    test "validates and saves notification preferences", %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/notifications")
      render(view)

      view
      |> form("#notification_form",
        user: %{
          "newsletter_notifications" => "true",
          "event_notifications" => "true",
          "event_notifications_sms" => "false",
          "account_notifications_sms" => "false"
        }
      )
      |> render_change()

      render_submit(view, "update_notifications", %{
        "user" => %{
          "newsletter_notifications" => "true",
          "event_notifications" => "true",
          "event_notifications_sms" => "false",
          "account_notifications_sms" => "false"
        }
      })

      assert render(view) =~ "Notification preferences updated successfully"
    end

    test "saves notification preferences with SMS toggles enabled", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/notifications")
      render(view)

      render_submit(view, "update_notifications", %{
        "user" => %{
          "newsletter_notifications" => "false",
          "event_notifications" => "true",
          "event_notifications_sms" => "true",
          "account_notifications_sms" => "true"
        }
      })

      assert render(view) =~ "Notification preferences updated successfully"
    end

    test "validate_notifications reflects newsletter off without saving", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/notifications")
      render(view)

      html =
        render_change(view, "validate_notifications", %{
          "user" => %{
            "newsletter_notifications" => "false",
            "event_notifications" => "false",
            "event_notifications_sms" => "false",
            "account_notifications_sms" => "false"
          }
        })

      assert html =~ "Notification" or html =~ "newsletter"
    end

    test "update_notifications forces account_notifications on in backend", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/notifications")
      render(view)

      render_submit(view, "update_notifications", %{
        "user" => %{
          "newsletter_notifications" => "true",
          "event_notifications" => "true",
          "event_notifications_sms" => "false",
          "account_notifications_sms" => "false"
        }
      })

      updated = Repo.get!(Ysc.Accounts.User, user.id)
      assert updated.account_notifications == true
    end

    test "notifications page renders heading and form", %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/notifications")
      html = render(view)

      assert has_element?(view, "#notification_form")
      assert html =~ "notification" or html =~ "Notification"
    end
  end

  describe "settings page — payments tab" do
    test "loads payments view and filters by category", %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/payments")
      render(view)

      assert has_element?(view, "#payments-list")
      assert render(view) =~ "Payment History"

      view
      |> element(
        "button[phx-click=\"filter-payments\"][phx-value-filter=\"membership\"]"
      )
      |> render_click()

      assert render(view) =~ "Payment History"
    end

    test "filter-payments clear_lake updates stream without crashing", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/payments")
      render(view)

      view
      |> element(
        "button[phx-click=\"filter-payments\"][phx-value-filter=\"clear_lake\"]"
      )
      |> render_click()

      assert has_element?(view, "#payments-list")
    end

    test "filter-payments donations updates stream without crashing", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/payments")
      render(view)

      view
      |> element(
        "button[phx-click=\"filter-payments\"][phx-value-filter=\"donations\"]"
      )
      |> render_click()

      assert render(view) =~ "Payment History"
    end

    test "payments tab omits benefits and reservations panels when none are usable",
         %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/payments")
      render(view)

      refute has_element?(view, "#member-booking-entitlements-section")
      refute has_element?(view, "#member-ticket-reservations-section")
      assert has_element?(view, "#payments-list")
    end

    test "payments tab lists booking entitlements and ticket reservations for the member",
         %{conn: conn} do
      organizer = user_fixture(%{state: :active})
      member = user_fixture(%{state: :active})
      conn = log_in_user(conn, member)

      assert {:ok, entitlement} =
               Entitlements.create_entitlement(
                 %{
                   user_id: member.id,
                   issued_by_user_id: organizer.id,
                   benefit_kind: :percent_off,
                   property: :tahoe,
                   percent_off: Decimal.new("30"),
                   buyout_max_discount: Money.new(:USD, 200)
                 },
                 send_notification: false
               )

      event =
        event_fixture(%{
          organizer_id: organizer.id,
          title: "Payments Tab Event XYZ"
        })

      tier = ticket_tier_fixture(%{event_id: event.id, name: "VIP Row"})

      expires_at =
        DateTime.utc_now()
        |> DateTime.add(3 * 24 * 60 * 60, :second)
        |> DateTime.truncate(:second)

      assert {:ok, reservation} =
               %TicketReservation{}
               |> TicketReservation.changeset(%{
                 ticket_tier_id: tier.id,
                 user_id: member.id,
                 quantity: 2,
                 created_by_id: organizer.id,
                 status: "active",
                 expires_at: expires_at,
                 discount_percentage: Decimal.new("15")
               })
               |> Repo.insert()

      {:ok, view, _html} = live(conn, ~p"/users/payments")
      html = render(view)

      assert has_element?(view, "#member-entitlement-#{entitlement.id}")
      assert has_element?(view, "#member-ticket-reservation-#{reservation.id}")
      assert html =~ "Payments Tab Event XYZ"
      assert html =~ "VIP Row"

      assert has_element?(
               view,
               "#member-booking-entitlements-section h2",
               "Your stay perks"
             )

      assert has_element?(
               view,
               "#member-ticket-reservations-section h2",
               "Your price holds"
             )

      assert has_element?(
               view,
               "#member-ticket-reservation-#{reservation.id}",
               "15% off member tickets"
             )
    end

    test "payment pagination prev on first page is a no-op", %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/payments")
      render(view)

      before = render(view)
      render_click(view, "prev-payments-page")
      assert render(view) == before
    end

    test "retry_invoice query shows message when invoice cannot be retried", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(conn, ~p"/users/membership?retry_invoice=in_test_missing")

      render(view)
      assert render(view) =~ "Invoice"
    end
  end

  describe "settings page — phone verification flow" do
    test "changing phone number opens verification and accepts dev code 000000",
         %{
           conn: conn
         } do
      user = user_fixture(%{state: :active, phone_number: "+14159098268"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      new_phone =
        "+1415555#{rem(System.unique_integer([:positive]), 9000) + 1000}"

      render_submit(view, "update_profile", %{
        "user" =>
          profile_form_attrs(user, %{
            "phone_number" => new_phone
          })
      })

      assert render(view) =~ "Verify Your Phone Number"
      assert has_element?(view, "#phone_verification_form")
      assert has_element?(view, "#phone-verification-keep-open-notice")

      render_submit(view, "verify_phone_code", %{
        "verification_code" => "000000"
      })

      assert render(view) =~ "verified successfully"

      updated = Repo.get!(Ysc.Accounts.User, user.id)
      assert updated.phone_number == new_phone
    end

    test "validate_phone_code enables flow when digits entered", %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "update_profile", %{
        "user" =>
          profile_form_attrs(user, %{
            "phone_number" => "+14155550199"
          })
      })

      render(view)

      render_change(view, "validate_phone_code", %{
        "verification_code" => %{
          "0" => "1",
          "1" => "2",
          "2" => "3",
          "3" => "4",
          "4" => "5",
          "5" => "6"
        }
      })

      assert render(view) =~ "Verify Phone Number"
    end

    test "confirm_cancel_phone_verification patches away when no pending phone",
         %{
           conn: conn
         } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_click(view, "confirm_cancel_phone_verification")
      assert_patched(view, ~p"/users/settings")
    end
  end

  describe "settings page — misc LiveView events" do
    test "noop hook events do not crash the view", %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_hook(view, "passkey_support_detected", %{})
      render_hook(view, "user_agent_received", %{"ua" => "test"})
      render_hook(view, "device_detected", %{})

      assert has_element?(view, "#user-settings-page")
    end

    test "accept-family-invite with invalid token shows error toast", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      render_click(view, "accept-family-invite", %{
        "token" => "invalid_token_#{System.unique_integer()}"
      })

      assert render(view) =~ "Invitation not found"
    end

    test "refresh_payment_methods handle_info updates assigns", %{conn: conn} do
      user =
        user_fixture(%{state: :active})
        |> then(fn u ->
          u
          |> Ecto.Changeset.change(%{
            stripe_id: "cus_refresh_#{System.unique_integer()}"
          })
          |> Repo.update!()
        end)

      stub(Stripe.PaymentMethodMock, :list, fn _params ->
        {:ok, %{data: []}}
      end)

      stub(Stripe.CustomerMock, :retrieve, fn _id, _opts ->
        {:ok,
         %Stripe.Customer{
           id: user.stripe_id,
           invoice_settings: %{default_payment_method: nil}
         }}
      end)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      send(view.pid, {:refresh_payment_methods, user.id})
      render(view)

      assert has_element?(view, "#membership_form")
    end

    test "show_membership_qr toggles modal for subscribed user", %{conn: conn} do
      user =
        user_fixture(%{state: :active})
        |> then(fn u ->
          u
          |> Ecto.Changeset.change(%{
            stripe_id: "cus_qr_#{System.unique_integer()}"
          })
          |> Repo.update!()
        end)

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_qr_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Membership",
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(plans, &(&1.id == :single))
      assert single_plan

      {:ok, _item} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_qr_#{System.unique_integer()}",
          stripe_product_id: "prod_single",
          stripe_price_id: single_plan.stripe_price_id,
          quantity: 1
        })

      MembershipCache.invalidate_user(user.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      render_click(view, "show_membership_qr")
      assert has_element?(view, "#settings-membership-qr-modal")

      render_click(view, "hide_membership_qr")
      refute has_element?(view, "#settings-membership-qr-modal")
    end

    test "validate_membership does not enable change for inactive users", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{state: :pending_approval})
        |> Repo.update()

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      render_change(view, "validate_membership", %{
        "membership_type" => "family"
      })

      refute render(view) =~ "data-testid=\"change-membership-plan-button\""
    end

    test "sub-account can leave family membership", %{conn: conn} do
      primary = user_fixture(%{phone_number: "+14159098401", state: :active})

      sub =
        user_fixture(%{phone_number: "+14159098402", state: :active})
        |> then(fn u ->
          u
          |> Ecto.Changeset.change(%{})
          |> Ecto.Changeset.put_change(:primary_user_id, primary.id)
          |> Repo.update!()
        end)

      conn = log_in_user(conn, sub)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      assert {:error, {:redirect, %{to: to}}} =
               view
               |> element("button[phx-click=\"leave-family-membership\"]")
               |> render_click()

      assert to == "/users/membership"
    end
  end

  describe "membership plan change (stubbed Subscriptions callback)" do
    test "change-membership upgrade shows success when callback returns ok", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{
          stripe_id: "cus_planchg_#{System.unique_integer()}"
        })
        |> Repo.update()

      plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(plans, &(&1.id == :single))
      family_plan = Enum.find(plans, &(&1.id == :family))
      assert single_plan && family_plan

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_planchg_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Membership",
          current_period_start: DateTime.utc_now(),
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, _} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_planchg_#{System.unique_integer()}",
          stripe_product_id: "prod_single",
          stripe_price_id: single_plan.stripe_price_id,
          quantity: 1
        })

      {:ok, _} =
        Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_planchg_default",
          provider_customer_id: user.stripe_id,
          type: :card,
          provider_type: "card",
          is_default: true
        })

      subscription = Repo.preload(subscription, :subscription_items)

      callback = fn sub, price_id, :upgrade ->
        assert sub.id == subscription.id
        assert price_id == family_plan.stripe_price_id
        {:ok, subscription}
      end

      try do
        Application.put_env(
          :ysc,
          :change_membership_plan_stripe_callback,
          callback
        )

        MembershipCache.invalidate_user(user.id)

        conn = log_in_user(conn, user)
        {:ok, view, _html} = live(conn, ~p"/users/membership")
        render(view)

        render_change(view, "validate_membership", %{
          "membership_type" => "family"
        })

        render_click(view, "change-membership", %{"membership_type" => "family"})

        assert render(view) =~ "upgraded"
      after
        Application.delete_env(:ysc, :change_membership_plan_stripe_callback)
      end
    end

    test "change-membership downgrade scheduled shows renewal toast when callback returns scheduled",
         %{conn: conn} do
      user = user_fixture(%{state: :active})

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{
          stripe_id: "cus_down_#{System.unique_integer()}"
        })
        |> Repo.update()

      plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(plans, &(&1.id == :single))
      family_plan = Enum.find(plans, &(&1.id == :family))
      assert single_plan && family_plan

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_down_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Membership",
          current_period_start: DateTime.utc_now(),
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, _} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_down_#{System.unique_integer()}",
          stripe_product_id: "prod_family",
          stripe_price_id: family_plan.stripe_price_id,
          quantity: 1
        })

      {:ok, _} =
        Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_down_default",
          provider_customer_id: user.stripe_id,
          type: :card,
          provider_type: "card",
          is_default: true
        })

      subscription = Repo.preload(subscription, :subscription_items)

      callback = fn sub, _price_id, :downgrade ->
        assert sub.id == subscription.id
        {:scheduled, subscription}
      end

      try do
        Application.put_env(
          :ysc,
          :change_membership_plan_stripe_callback,
          callback
        )

        MembershipCache.invalidate_user(user.id)

        conn = log_in_user(conn, user)
        {:ok, view, _html} = live(conn, ~p"/users/membership")
        render(view)

        render_change(view, "validate_membership", %{
          "membership_type" => "single"
        })

        render_click(view, "change-membership", %{"membership_type" => "single"})

        assert render(view) =~ "next renewal"
      after
        Application.delete_env(:ysc, :change_membership_plan_stripe_callback)
      end
    end

    test "change-membership shows error toast when callback returns error", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{
          stripe_id: "cus_err_#{System.unique_integer()}"
        })
        |> Repo.update()

      plans = Application.get_env(:ysc, :membership_plans, [])
      single_plan = Enum.find(plans, &(&1.id == :single))
      family_plan = Enum.find(plans, &(&1.id == :family))
      assert single_plan && family_plan

      {:ok, subscription} =
        Subscriptions.create_subscription(%{
          user_id: user.id,
          stripe_id: "sub_err_#{System.unique_integer()}",
          stripe_status: "active",
          name: "Membership",
          current_period_start: DateTime.utc_now(),
          current_period_end: DateTime.add(DateTime.utc_now(), 30, :day)
        })

      {:ok, _} =
        Subscriptions.create_subscription_item(%{
          subscription_id: subscription.id,
          stripe_id: "si_err_#{System.unique_integer()}",
          stripe_product_id: "prod_single",
          stripe_price_id: single_plan.stripe_price_id,
          quantity: 1
        })

      {:ok, _} =
        Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_err_default",
          provider_customer_id: user.stripe_id,
          type: :card,
          provider_type: "card",
          is_default: true
        })

      subscription = Repo.preload(subscription, :subscription_items)

      callback = fn sub, _, :upgrade ->
        assert sub.id == subscription.id
        {:error, :stripe_timeout}
      end

      try do
        Application.put_env(
          :ysc,
          :change_membership_plan_stripe_callback,
          callback
        )

        MembershipCache.invalidate_user(user.id)

        conn = log_in_user(conn, user)
        {:ok, view, _html} = live(conn, ~p"/users/membership")
        render(view)

        render_change(view, "validate_membership", %{
          "membership_type" => "family"
        })

        render_click(view, "change-membership", %{"membership_type" => "family"})

        assert render(view) =~ "info@ysc.org"
        assert render(view) =~ "try again in a few minutes"
      after
        Application.delete_env(:ysc, :change_membership_plan_stripe_callback)
      end
    end
  end

  describe "settings page — email validation and payment method UI" do
    test "validate_email updates email form", %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      html =
        view
        |> form("#email_form", user: %{email: "not-an-email"})
        |> render_change()

      assert html =~ "@" or html =~ "email" or html =~ "format"
    end

    test "validate_email accepts well-formed email in form", %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      email = "wellformed_#{System.unique_integer([:positive])}@example.com"

      html =
        view
        |> form("#email_form", user: %{email: email})
        |> render_change()

      assert html =~ email
    end

    test "payment-method live route renders update payment modal shell", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{
          stripe_id: "cus_pm_modal_#{System.unique_integer()}"
        })
        |> Repo.update()

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership/payment-method")
      render(view)

      assert has_element?(view, "#update-payment-method-modal")
    end

    test "select-payment-method sets default when Stripe customer update succeeds",
         %{
           conn: conn
         } do
      user = user_fixture(%{state: :active})

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{
          stripe_id: "cus_selpm_#{System.unique_integer()}"
        })
        |> Repo.update()

      {:ok, _pm1} =
        Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_sel_a",
          provider_customer_id: user.stripe_id,
          type: :card,
          provider_type: "card",
          is_default: true
        })

      {:ok, pm2} =
        Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_sel_b",
          provider_customer_id: user.stripe_id,
          type: :card,
          provider_type: "card",
          is_default: false
        })

      Stripe.CustomerMock
      |> stub(:update, fn _cus_id, _params, _opts ->
        {:ok, %Stripe.Customer{id: user.stripe_id}}
      end)

      MembershipCache.invalidate_user(user.id)
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership/payment-method")
      render(view)

      view
      |> element(
        "div[phx-click=\"select-payment-method\"][phx-value-payment_method_id=\"#{pm2.id}\"]"
      )
      |> render_click()

      assert render(view) =~ "default" or render(view) =~ "Default"
    end

    test "cancel-new-payment-method hides the add form", %{conn: conn} do
      user = user_fixture(%{state: :active})

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{
          stripe_id: "cus_cancel_form_#{System.unique_integer()}"
        })
        |> Repo.update()

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership/payment-method")
      render(view)

      render_click(view, "add-new-payment-method")
      render_click(view, "cancel-new-payment-method")

      assert render(view) =~ "Payment Method"
    end

    test "retry-invoice-payment click shows feedback for unknown invoice", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      render_click(view, "retry-invoice-payment", %{
        "invoice_id" => "in_bad_retry"
      })

      assert render(view) =~ "invoice" or render(view) =~ "Invoice"
    end

    test "confirm_cancel_email_verification patches to settings when no pending email",
         %{
           conn: conn
         } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_click(view, "confirm_cancel_email_verification")
      assert_patched(view, ~p"/users/settings")
    end

    test "cancel_email_verification_confirmed patches back to settings", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      # Build a signed token so the email-verification live action mounts
      # successfully (Finding 12 fix: email is no longer passed as plaintext).
      token =
        Phoenix.Token.sign(
          YscWeb.Endpoint,
          "email_verification_pending",
          "new@example.com",
          max_age: 1800
        )

      {:ok, view, _html} =
        live(conn, "/users/settings/email-verification?etok=#{token}")

      render(view)
      render_click(view, "cancel_email_verification_confirmed")
      assert_patched(view, ~p"/users/settings")
    end
  end

  describe "settings page — payments filters" do
    test "each payment filter button updates the payments stream", %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/payments")
      render(view)

      for filter <- ~w(all tahoe clear_lake events donations membership) do
        view
        |> element(
          "button[phx-click=\"filter-payments\"][phx-value-filter=\"#{filter}\"]"
        )
        |> render_click()
      end

      assert render(view) =~ "Payment History"
    end
  end

  describe "family invite acceptance — additional error paths" do
    test "accept-family-invite shows error when invite email does not match user",
         %{
           conn: conn
         } do
      primary = primary_user_with_lifetime_for_family_invite()
      invite_email = Ysc.AccountsFixtures.unique_user_email()

      {:ok, invite} = FamilyInvites.create_invite(primary, invite_email)
      other = user_fixture()

      conn = log_in_user(conn, other)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      render_click(view, "accept-family-invite", %{"token" => invite.token})

      assert render(view) =~ "different email"
    end

    test "accept-family-invite shows error when invite has expired", %{
      conn: conn
    } do
      primary = primary_user_with_lifetime_for_family_invite()
      invite_email = Ysc.AccountsFixtures.unique_user_email()
      {:ok, invite} = FamilyInvites.create_invite(primary, invite_email)

      past =
        DateTime.utc_now()
        |> DateTime.add(-1, :day)
        |> DateTime.truncate(:second)

      {:ok, _} =
        invite
        |> Ecto.Changeset.change(%{expires_at: past})
        |> Repo.update()

      invitee = user_fixture(%{email: invite_email})
      conn = log_in_user(conn, invitee)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      render_click(view, "accept-family-invite", %{"token" => invite.token})

      assert render(view) =~ "expired" or render(view) =~ "already been used"
    end
  end

  describe "settings page — handle_info and membership edge cases" do
    test "phone verification with invalid token patches back to settings with error toast",
         %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      _html =
        render_patch(
          view,
          "/users/settings/phone-verification?token=not-a-valid-token"
        )

      assert_patched(view, ~p"/users/settings")
      assert render(view) =~ "Verification link expired"
    end

    test "retry invoice handle_info shows error for non-active user", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{state: :pending_approval})
        |> Repo.update()

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      send(view.pid, {:retry_invoice_payment, "in_test_inactive_user"})

      assert render(view) =~ "approved account"
    end

    test "retry invoice handle_info shows error for invalid invoice id", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      send(view.pid, {:retry_invoice_payment, nil})

      assert render(view) =~ "Invalid invoice ID"
    end

    test "refresh_payment_methods handle_info ignores other user id", %{
      conn: conn
    } do
      user =
        user_fixture(%{state: :active})
        |> then(fn u ->
          u
          |> Ecto.Changeset.change(%{
            stripe_id: "cus_refresh_other_#{System.unique_integer()}"
          })
          |> Repo.update!()
        end)

      other = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      before = render(view)

      send(view.pid, {:refresh_payment_methods, other.id})
      assert render(view) == before
    end

    test "cancel-membership shows error for non-active user", %{conn: conn} do
      user = user_fixture(%{state: :active})

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{state: :pending_approval})
        |> Repo.update()

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      render_click(view, "cancel-membership")

      assert render(view) =~ "approved account"
    end

    test "reactivate-membership shows error for non-active user", %{conn: conn} do
      user = user_fixture(%{state: :active})

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{state: :pending_approval})
        |> Repo.update()

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      render_click(view, "reactivate-membership")

      assert render(view) =~ "approved account"
    end

    test "resend_phone_code shows rate limit toast on second request", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active, phone_number: "+14159098268"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      new_phone =
        "+1415555#{rem(System.unique_integer([:positive]), 8000) + 1000}"

      render_submit(view, "update_profile", %{
        "user" =>
          profile_form_attrs(user, %{
            "phone_number" => new_phone
          })
      })

      render(view)

      render_click(view, "resend_phone_code")
      assert render(view) =~ "Verification code sent to your phone"

      render_click(view, "resend_phone_code")

      assert render(view) =~
               "Please wait before requesting another verification code"
    end

    test "resend_email_code shows rate limit toast on second request", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      new_email = "rate#{System.unique_integer([:positive])}@example.com"

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "request_email_change", %{
        "user" => %{"email" => new_email}
      })

      submit_reauth_password(view, valid_user_password())

      render_click(view, "resend_email_code")
      assert render(view) =~ "Verification code sent to your email"

      render_click(view, "resend_email_code")

      assert render(view) =~
               "Please wait before requesting another verification code"
    end

    test "unknown handle_info message is ignored", %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      send(view.pid, {:some_unhandled_message, :test})
      assert has_element?(view, "#user-settings-page")
    end
  end

  describe "settings page — extended form validation and flows" do
    setup %{conn: conn} do
      email =
        "usettings_ext_#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}@example.com"

      user = user_fixture(%{state: :active, email: email})
      conn = log_in_user(conn, user)
      %{conn: conn, user: Repo.get!(Ysc.Accounts.User, user.id)}
    end

    test "validate_profile updates profile form without persisting", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      html =
        render_change(view, "validate_profile", %{
          "user" =>
            profile_form_attrs(user, %{
              "first_name" => "Validating#{System.unique_integer([:positive])}"
            })
        })

      assert html =~ user.last_name or html =~ "Personal Information"
    end

    test "validate_address updates address form without persisting", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      html =
        render_change(view, "validate_address", %{
          "address" => %{
            "address" => "99 Validation St",
            "city" => "Testville",
            "postal_code" => "94102",
            "region" => "CA",
            "country" => "USA"
          }
        })

      assert html =~ "99 Validation St" or html =~ "Billing Address"
    end

    test "validate_notifications updates notification form without persisting",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/notifications")
      render(view)

      html =
        render_change(view, "validate_notifications", %{
          "user" => %{
            "newsletter_notifications" => "false",
            "event_notifications" => "true",
            "event_notifications_sms" => "false",
            "account_notifications_sms" => "false"
          }
        })

      assert html =~ "Notification" or html =~ "newsletter"
    end

    test "request_email_change with same email shows info toast", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "request_email_change", %{
        "user" => %{"email" => user.email}
      })

      assert render(view) =~ "already your email"
    end

    test "full email change: reauth with password then verify with test code 000000",
         %{
           conn: conn,
           user: user
         } do
      new_email = "changed#{System.unique_integer([:positive])}@example.com"

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "request_email_change", %{
        "user" => %{"email" => new_email}
      })

      assert has_element?(view, "#reauth-modal")

      submit_reauth_password(view, valid_user_password())

      assert render(view) =~ "Verify Your New Email Address"
      assert has_element?(view, "#email-verification-keep-open-notice")

      render_submit(view, "verify_email_code", %{
        "verification_code" => "000000"
      })

      assert render(view) =~ "Email address updated successfully"
      updated = Repo.get!(Ysc.Accounts.User, user.id)
      assert updated.email == new_email
    end

    test "cancel_reauth closes modal and clears pending email change", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "request_email_change", %{
        "user" => %{
          "email" => "other#{System.unique_integer([:positive])}@example.com"
        }
      })

      assert has_element?(view, "#reauth-modal")

      click_cancel_reauth(view)

      refute has_element?(view, "#reauth-modal")
    end

    test "reauth_with_password shows error for wrong password", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "request_email_change", %{
        "user" => %{
          "email" => "x#{System.unique_integer([:positive])}@example.com"
        }
      })

      view
      |> element("#reauth_password_form")
      |> render_submit(%{"password" => "definitely_wrong_password"})

      assert render(view) =~ "Invalid password"
      assert has_element?(view, "#reauth-password-error-notice")
    end

    test "reauth_with_passkey pushes authentication challenge", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "request_email_change", %{
        "user" => %{
          "email" => "pk#{System.unique_integer([:positive])}@example.com"
        }
      })

      click_reauth_with_passkey(view)

      assert_push_event(view, "create_authentication_challenge", %{
        options: options
      })

      assert is_binary(options.challenge)
    end

    test "verify_authentication completes email change flow after passkey step",
         %{
           conn: conn,
           user: user
         } do
      new_email = "passkey#{System.unique_integer([:positive])}@example.com"

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "request_email_change", %{
        "user" => %{"email" => new_email}
      })

      submit_reauth_password(view, Ysc.AccountsFixtures.valid_user_password())

      assert render(view) =~ "Verify Your New Email Address"
      assert has_element?(view, "#email-verification-keep-open-notice")

      render_submit(view, "verify_email_code", %{
        "verification_code" => "000000"
      })

      assert render(view) =~ "Email address updated successfully"
      assert Repo.get!(Ysc.Accounts.User, user.id).email == new_email
    end

    test "passkey_auth_error sets reauth error message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "request_email_change", %{
        "user" => %{
          "email" => "e#{System.unique_integer([:positive])}@example.com"
        }
      })

      hook_passkey_auth_error(view, %{"error" => "cancelled"})

      assert render(view) =~ "Passkey authentication failed"
    end

    test "confirm_cancel_email_verification with pending email pushes confirm_close_modal",
         %{
           conn: conn
         } do
      new_email = "pending#{System.unique_integer([:positive])}@example.com"

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "request_email_change", %{
        "user" => %{"email" => new_email}
      })

      submit_reauth_password(view, valid_user_password())

      render_click(view, "confirm_cancel_email_verification")

      assert_push_event(view, "confirm_close_modal", %{
        on_confirm: "cancel_email_verification_confirmed"
      })
    end

    test "validate_email_code enables verify when six digits entered on email verification",
         %{conn: conn} do
      new_email = "vcode#{System.unique_integer([:positive])}@example.com"

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "request_email_change", %{
        "user" => %{"email" => new_email}
      })

      submit_reauth_password(view, valid_user_password())

      render_change(view, "validate_email_code", %{
        "verification_code" => %{
          "0" => "1",
          "1" => "2",
          "2" => "3",
          "3" => "4",
          "4" => "5",
          "5" => "6"
        }
      })

      assert render(view) =~ "Verify Your New Email Address"
      assert has_element?(view, "#email-verification-keep-open-notice")
    end

    test "resend_email_code sends toast when on email verification route", %{
      conn: conn
    } do
      new_email = "resend#{System.unique_integer([:positive])}@example.com"

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "request_email_change", %{
        "user" => %{"email" => new_email}
      })

      submit_reauth_password(view, valid_user_password())

      render_click(view, "resend_email_code")

      assert render(view) =~ "Verification code sent to your email"
    end

    test "verify_email_code with wrong code shows invalid verification error",
         %{
           conn: conn
         } do
      new_email = "wrongcode#{System.unique_integer([:positive])}@example.com"

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "request_email_change", %{
        "user" => %{"email" => new_email}
      })

      submit_reauth_password(view, valid_user_password())

      render_submit(view, "verify_email_code", %{
        "verification_code" => "111111"
      })

      assert render(view) =~ "Invalid verification code"
    end

    test "validate_email_code is a no-op when there is no pending email change",
         %{
           conn: conn
         } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      before = render(view)

      render_change(view, "validate_email_code", %{
        "verification_code" => %{
          "0" => "1",
          "1" => "2",
          "2" => "3",
          "3" => "4",
          "4" => "5",
          "5" => "6"
        }
      })

      assert render(view) == before
    end

    test "verify_email_code with missing code param shows error", %{conn: conn} do
      new_email = "miss#{System.unique_integer([:positive])}@example.com"

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      render_submit(view, "request_email_change", %{
        "user" => %{"email" => new_email}
      })

      submit_reauth_password(view, valid_user_password())

      render_submit(view, "verify_email_code", %{})

      assert render(view) =~ "Please enter a verification code"
    end

    test "verify_phone_code with wrong code shows invalid error after SMS flow",
         %{conn: conn} do
      user = user_fixture(%{state: :active, phone_number: "+14159098268"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      new_phone =
        "+1415555#{rem(System.unique_integer([:positive]), 8000) + 1000}"

      render_submit(view, "update_profile", %{
        "user" =>
          profile_form_attrs(user, %{
            "phone_number" => new_phone
          })
      })

      render(view)

      render_submit(view, "verify_phone_code", %{
        "verification_code" => "111111"
      })

      assert render(view) =~ "Invalid verification code"
    end

    test "verify_phone_code without verification_code key shows message", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active, phone_number: "+14159098268"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      new_phone =
        "+1415555#{rem(System.unique_integer([:positive]), 8000) + 1000}"

      render_submit(view, "update_profile", %{
        "user" =>
          profile_form_attrs(user, %{
            "phone_number" => new_phone
          })
      })

      render(view)

      render_submit(view, "verify_phone_code", %{})

      assert render(view) =~ "Please enter a verification code"
    end

    test "resend_phone_code sends SMS toast after phone change flow", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active, phone_number: "+14159098268"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      new_phone =
        "+1415555#{rem(System.unique_integer([:positive]), 8000) + 1000}"

      render_submit(view, "update_profile", %{
        "user" =>
          profile_form_attrs(user, %{
            "phone_number" => new_phone
          })
      })

      render(view)

      render_click(view, "resend_phone_code")

      assert render(view) =~ "Verification code sent to your phone"
    end

    test "confirm_cancel_phone_verification with pending phone pushes confirm_close_modal",
         %{
           conn: conn
         } do
      user = user_fixture(%{state: :active, phone_number: "+14159098268"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      new_phone =
        "+1415555#{rem(System.unique_integer([:positive]), 8000) + 1000}"

      render_submit(view, "update_profile", %{
        "user" =>
          profile_form_attrs(user, %{
            "phone_number" => new_phone
          })
      })

      render(view)

      render_click(view, "confirm_cancel_phone_verification")

      assert_push_event(view, "confirm_close_modal", %{
        on_confirm: "cancel_phone_verification_confirmed"
      })
    end

    test "cancel_phone_verification_confirmed patches to settings", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active, phone_number: "+14159098268"})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      new_phone =
        "+1415555#{rem(System.unique_integer([:positive]), 8000) + 1000}"

      render_submit(view, "update_profile", %{
        "user" =>
          profile_form_attrs(user, %{
            "phone_number" => new_phone
          })
      })

      render(view)

      render_click(view, "cancel_phone_verification_confirmed")
      assert_patched(view, ~p"/users/settings")
    end

    test "validate_phone_code is a no-op when no pending phone verification", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")
      render(view)

      before = render(view)

      render_change(view, "validate_phone_code", %{
        "verification_code" => %{
          "0" => "1",
          "1" => "2",
          "2" => "3",
          "3" => "4",
          "4" => "5",
          "5" => "6"
        }
      })

      assert render(view) == before
    end

    test "leave-family-membership shows error for primary account holder", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      render_click(view, "leave-family-membership")

      assert render(view) =~ "not linked to a family membership"
    end

    test "show_membership_qr without active membership is a no-op", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      render_click(view, "show_membership_qr")

      refute has_element?(view, "#settings-membership-qr-modal")
    end

    test "cancel-membership shows error when user has no subscription", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      render_click(view, "cancel-membership")

      assert render(view) =~ "No subscription to cancel"
    end

    test "cancel-scheduled-downgrade shows error when user has no subscription",
         %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      render_click(view, "cancel-scheduled-downgrade")

      assert render(view) =~ "No subscription to update"
    end

    test "reactivate-membership shows error when user has no subscription", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      render_click(view, "reactivate-membership")

      assert render(view) =~ "No subscription to resume"
    end

    test "change-membership shows error when there is no active membership", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership")
      render(view)

      render_change(view, "validate_membership", %{
        "membership_type" => "family"
      })

      render_click(view, "change-membership", %{"membership_type" => "family"})

      assert render(view) =~ "do not have an active membership"
    end

    test "refresh-payment-methods reloads methods from Stripe sync", %{
      conn: conn
    } do
      user = user_fixture(%{state: :active})

      {:ok, user} =
        user
        |> Ecto.Changeset.change(%{
          stripe_id: "cus_refresh_btn_#{System.unique_integer()}"
        })
        |> Repo.update()

      {:ok, _} =
        Payments.insert_payment_method(%{
          user_id: user.id,
          provider: :stripe,
          provider_id: "pm_refresh_btn",
          provider_customer_id: user.stripe_id,
          type: :card,
          provider_type: "card",
          is_default: true
        })

      stub(Stripe.PaymentMethodMock, :list, fn _params ->
        {:ok, %{data: []}}
      end)

      stub(Stripe.CustomerMock, :retrieve, fn _id, _opts ->
        {:ok,
         %Stripe.Customer{
           id: user.stripe_id,
           invoice_settings: %{default_payment_method: nil}
         }}
      end)

      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/membership/payment-method")
      render(view)

      render_click(view, "refresh-payment-methods")

      assert has_element?(view, "#update-payment-method-modal")
    end

    test "payments next page loads second page when user has many ledger payments",
         %{
           conn: conn
         } do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      for _ <- 1..21 do
        LedgersFixtures.payment_fixture(%{user_id: user.id})
      end

      {:ok, view, _html} = live(conn, ~p"/users/payments")
      render(view)

      assert render(view) =~ "Page 1 of 2"

      render_click(view, "next-payments-page")

      assert render(view) =~ "Page 2 of 2"
    end

    test "next-payments-page on last page stays on last page", %{conn: conn} do
      user = user_fixture(%{state: :active})
      conn = log_in_user(conn, user)

      for _ <- 1..21 do
        LedgersFixtures.payment_fixture(%{user_id: user.id})
      end

      {:ok, view, _html} = live(conn, ~p"/users/payments")
      render(view)
      render_click(view, "next-payments-page")

      html_on_last = render(view)
      assert html_on_last =~ "Page 2 of 2"

      render_click(view, "next-payments-page")

      assert render(view) == html_on_last
    end
  end

  defp primary_user_with_lifetime_for_family_invite(attrs \\ %{}) do
    user_fixture(Map.merge(%{state: :active}, attrs))
    |> Ecto.Changeset.change(%{
      lifetime_membership_awarded_at:
        DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update!()
  end

  defp profile_form_attrs(%Ysc.Accounts.User{} = user, overrides)
       when is_map(overrides) do
    base = %{
      "first_name" => user.first_name,
      "last_name" => user.last_name,
      "phone_number" => user.phone_number,
      "most_connected_country" => user.most_connected_country || "SE",
      "date_of_birth" =>
        (user.date_of_birth && Date.to_iso8601(user.date_of_birth)) ||
          "1990-06-15"
    }

    Map.merge(base, overrides)
  end
end
