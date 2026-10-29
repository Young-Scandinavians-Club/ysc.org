defmodule YscWeb.Authorization.PolicyMatrixTest do
  @moduledoc """
  Keeps `YscWeb.Authorization.Policy` in step with the app.

  It fails when a schema has no policy object (or an object has no schema),
  and when the outcome of any rule changes for anonymous users, members,
  volunteers, admins or the record's owner. When it fails, decide the rule on
  purpose, update the policy, then update the table below to match.
  """
  use Ysc.DataCase, async: true

  alias Ysc.Accounts.User
  alias YscWeb.Authorization.Policy

  # Every Ecto schema in the app and the policy object that governs it.
  @schema_objects %{
    Ysc.Accounts.Address => :address,
    Ysc.Accounts.AuthEvent => :auth_event,
    Ysc.Accounts.BoardPosition => :board_position,
    Ysc.Accounts.FamilyInvite => :family_invite,
    Ysc.Accounts.FamilyMember => :family_member,
    Ysc.Accounts.SignupApplication => :signup_application,
    Ysc.Accounts.SignupApplicationEvent => :signup_application_event,
    Ysc.Accounts.User => :user,
    Ysc.Accounts.UserEvent => :user_event,
    Ysc.Accounts.UserNote => :user_note,
    Ysc.Accounts.UserPasskey => :user_passkey,
    Ysc.Accounts.UserToken => :user_token,
    Ysc.Avatars.Avatar => :avatar,
    Ysc.Bookings.Blackout => :blackout,
    Ysc.Bookings.Booking => :booking,
    Ysc.Bookings.BookingEntitlement => :booking_entitlement,
    Ysc.Bookings.BookingGuest => :booking_guest,
    Ysc.Bookings.BookingRoom => :booking_room,
    Ysc.Bookings.CheckIn => :check_in,
    Ysc.Bookings.CheckInBooking => :check_in_booking,
    Ysc.Bookings.CheckInVehicle => :check_in_vehicle,
    Ysc.Bookings.DoorCode => :door_code,
    Ysc.Bookings.PendingRefund => :pending_refund,
    Ysc.Bookings.PricingRule => :pricing_rule,
    Ysc.Bookings.PropertyInventory => :property_inventory,
    Ysc.Bookings.RefundPolicy => :refund_policy,
    Ysc.Bookings.RefundPolicyRule => :refund_policy_rule,
    Ysc.Bookings.Room => :room,
    Ysc.Bookings.RoomCategory => :room_category,
    Ysc.Bookings.RoomInventory => :room_inventory,
    Ysc.Bookings.Season => :season,
    Ysc.EventPhotos.Collection => :event_photos_collection,
    Ysc.Events.Agenda => :agenda,
    Ysc.Events.AgendaItem => :agenda_item,
    Ysc.Events.Event => :event,
    Ysc.Events.EventNotificationSubscription =>
      :event_notification_subscription,
    Ysc.Events.EventUpdate => :event_update,
    Ysc.Events.FaqQuestion => :faq_question,
    Ysc.Events.Ticket => :ticket,
    Ysc.Events.TicketDetail => :ticket_detail,
    Ysc.Events.TicketReservation => :ticket_reservation,
    Ysc.Events.TicketTier => :ticket_tier,
    Ysc.ExpenseReports.BankAccount => :bank_account,
    Ysc.ExpenseReports.ExpenseReport => :expense_report,
    Ysc.ExpenseReports.ExpenseReportIncomeItem => :expense_report_income_item,
    Ysc.ExpenseReports.ExpenseReportItem => :expense_report_item,
    Ysc.Forms.ConductViolationReport => :conduct_violation,
    Ysc.Forms.ContactForm => :contact_form,
    Ysc.Forms.Volunteer => :volunteer,
    Ysc.GooglePhotos.Connection => :google_photos_connection,
    Ysc.GooglePhotos.PosterAlbum => :google_photos_poster_album,
    Ysc.GooglePhotos.PosterItem => :google_photos_poster_item,
    Ysc.Ledgers.LedgerAccount => :ledger_account,
    Ysc.Ledgers.LedgerEntry => :ledger_entry,
    Ysc.Ledgers.LedgerTransaction => :ledger_transaction,
    Ysc.Ledgers.Payment => :payment,
    Ysc.Ledgers.Payout => :payout,
    Ysc.Ledgers.Refund => :refund,
    Ysc.Media.Image => :media_image,
    Ysc.Merch.CartItem => :merch_cart_item,
    Ysc.Merch.Order => :merch_order,
    Ysc.Merch.OrderItem => :merch_order_item,
    Ysc.Merch.Product => :merch_product,
    Ysc.Merch.ProductImage => :merch_product_image,
    Ysc.Merch.Shipment => :merch_shipment,
    Ysc.Merch.Variant => :merch_variant,
    Ysc.Messages.MessageIdempotency => :message_idempotency,
    Ysc.Newsletter.Edition => :newsletter_edition,
    Ysc.Newsletter.EmailEvent => :newsletter_email_event,
    Ysc.Newsletter.Notice => :newsletter_notice,
    Ysc.Newsletter.Subscriber => :newsletter_subscriber,
    Ysc.Newsletter.UnsubscribeEvent => :newsletter_unsubscribe_event,
    Ysc.Payments.PaymentMethod => :payment_method,
    Ysc.Posts.Comment => :comment,
    Ysc.Posts.Post => :post,
    Ysc.PropertyOutages.OutageTracker => :outage_tracker,
    Ysc.Scanning.ScanRecord => :scan_record,
    Ysc.Scanning.ScanSession => :scan_session,
    Ysc.Scanning.SessionCheckIn => :session_check_in,
    Ysc.SiteSettings.SiteSetting => :site_setting,
    Ysc.Sms.SmsDeliveryReceipt => :sms_delivery_receipt,
    Ysc.Sms.SmsMessage => :sms_message,
    Ysc.Sms.SmsReceived => :sms_received,
    Ysc.Subscriptions.Subscription => :subscription,
    Ysc.Subscriptions.SubscriptionItem => :subscription_item,
    Ysc.Tickets.TicketOrder => :ticket_order,
    Ysc.Webhooks.WebhookEvent => :webhook_event
  }

  # Schemas deliberately outside the policy: secrets that no role may read or
  # write through the UI, only the auth flows that issue and consume them,
  # plus a schema that exists only in the test environment.
  @excluded_schemas [
    Ysc.OAuth.AuthCode,
    Ysc.VerificationCode,
    Ysc.Ecto.DateKindSample
  ]

  # Policy objects with no table of their own.
  @virtual_objects [:family_sub_account, :admin_panel]

  # Who may perform each action on a record owned by somebody else:
  #
  #   public          everyone, including anonymous callers
  #   authenticated   any signed-in user
  #   staff           admin and volunteer
  #   admin           admin only
  #   owner_or_*      as above, plus the member who owns the record
  #   owner           only the owner (not even admin)
  #   denied          nobody
  @matrix %{
    public: ~w(
        address_create agenda_item_read agenda_read
        auth_event_create avatar_read board_position_read
        check_in_booking_create check_in_create check_in_vehicle_create
        comment_read conduct_violation_create contact_form_create
        event_read family_member_create faq_question_read
        media_image_read message_idempotency_create newsletter_email_event_create
        newsletter_subscriber_create newsletter_unsubscribe_event_create post_read
        refund_policy_read room_category_read room_read
        season_read signup_application_create site_setting_read
        sms_delivery_receipt_create sms_received_create ticket_tier_read
        user_create user_token_create volunteer_create
        webhook_event_create
      )a,
    authenticated: ~w(
        avatar_create bank_account_create booking_create
        booking_guest_create comment_create event_notification_subscription_create
        event_photos_collection_read expense_report_create merch_cart_item_create
        merch_order_create merch_order_item_create merch_product_image_read
        merch_product_read merch_variant_read payment_method_create
        ticket_order_create user_passkey_create
      )a,
    staff: ~w(
        agenda_create agenda_delete agenda_item_create
        agenda_item_delete agenda_item_update agenda_update
        event_create event_update event_update_create
        event_update_read faq_question_create faq_question_delete
        faq_question_update media_image_create media_image_delete
        media_image_update newsletter_edition_create newsletter_edition_delete
        newsletter_edition_read newsletter_edition_update newsletter_email_event_read
        newsletter_notice_create newsletter_notice_delete newsletter_notice_read
        newsletter_notice_update newsletter_subscriber_delete newsletter_subscriber_read
        newsletter_subscriber_update newsletter_unsubscribe_event_read post_create
        post_update scan_record_create scan_record_read
        scan_session_create session_check_in_create session_check_in_delete
        session_check_in_read
        admin_panel_access
        event_delete_draft
        event_publish
        event_read_unpublished
        post_read_unpublished
      )a,
    owner_or_staff: ~w(
        ticket_detail_create ticket_detail_read ticket_detail_update
        ticket_order_read ticket_read
      )a,
    admin: ~w(
        blackout_create blackout_delete blackout_read
        blackout_update board_position_create board_position_delete
        board_position_update booking_delete booking_entitlement_create
        booking_entitlement_delete booking_entitlement_update booking_room_create
        booking_room_delete booking_room_read booking_room_update
        check_in_booking_read check_in_read check_in_vehicle_read
        conduct_violation_read conduct_violation_update contact_form_delete
        contact_form_read contact_form_update door_code_create
        door_code_delete door_code_update event_delete
        event_photos_collection_create event_photos_collection_delete event_photos_collection_update
        expense_report_approve expense_report_reject family_invite_create
        google_photos_connection_create google_photos_connection_delete google_photos_connection_read
        google_photos_connection_update google_photos_poster_album_create google_photos_poster_album_delete
        google_photos_poster_album_read google_photos_poster_album_update google_photos_poster_item_create
        google_photos_poster_item_delete google_photos_poster_item_read google_photos_poster_item_update
        ledger_account_create ledger_account_read ledger_account_update
        ledger_entry_create ledger_entry_read ledger_transaction_create
        ledger_transaction_read merch_order_item_update merch_order_update
        merch_product_create merch_product_delete merch_product_image_create
        merch_product_image_delete merch_product_image_update merch_product_update
        merch_shipment_create merch_shipment_update merch_variant_create
        merch_variant_delete merch_variant_update message_idempotency_delete
        message_idempotency_read outage_tracker_create outage_tracker_delete
        outage_tracker_read outage_tracker_update payment_create
        payment_update payout_create payout_read
        payout_update pending_refund_create pending_refund_delete
        pending_refund_read pending_refund_update pricing_rule_create
        pricing_rule_delete pricing_rule_read pricing_rule_update
        property_inventory_create property_inventory_delete property_inventory_read
        property_inventory_update refund_create refund_policy_create
        refund_policy_delete refund_policy_rule_create refund_policy_rule_delete
        refund_policy_rule_read refund_policy_rule_update refund_policy_update
        refund_update room_category_create room_category_delete
        room_category_update room_create room_delete
        room_inventory_create room_inventory_delete room_inventory_read
        room_inventory_update room_update season_create
        season_delete season_update signup_application_event_create
        signup_application_event_read signup_application_update site_setting_create
        site_setting_delete site_setting_update sms_delivery_receipt_read
        sms_message_create sms_received_read subscription_create
        subscription_delete subscription_item_create subscription_item_delete
        subscription_item_update subscription_update ticket_create
        ticket_detail_delete ticket_reservation_create ticket_reservation_delete
        ticket_reservation_update ticket_tier_create ticket_tier_delete
        ticket_tier_update ticket_update user_event_create
        user_event_read user_note_create user_note_read
        user_update volunteer_delete volunteer_read
        volunteer_update webhook_event_delete webhook_event_read
        admin_panel_manage
        event_cancel
        event_unpublish
        merch_order_comp
        user_impersonate
      )a,
    owner_or_admin: ~w(
        address_delete address_read address_update
        auth_event_read avatar_delete avatar_update
        bank_account_delete bank_account_read bank_account_update
        booking_cancel booking_entitlement_read booking_guest_delete
        booking_guest_read booking_guest_update booking_read
        booking_update comment_delete comment_update
        door_code_read event_notification_subscription_delete event_notification_subscription_read
        event_notification_subscription_update expense_report_delete expense_report_income_item_create
        expense_report_income_item_delete expense_report_income_item_read expense_report_income_item_update
        expense_report_item_create expense_report_item_delete expense_report_item_read
        expense_report_item_update expense_report_read expense_report_submit
        expense_report_update family_invite_read family_invite_revoke
        family_member_delete family_member_read family_member_update
        family_sub_account_manage family_sub_account_read family_sub_account_remove
        merch_cart_item_delete merch_cart_item_read merch_cart_item_update
        merch_order_item_read merch_order_read merch_shipment_read
        payment_method_delete payment_method_read payment_method_update
        payment_read refund_read signup_application_read
        sms_message_read subscription_item_read subscription_read
        ticket_order_cancel ticket_order_update ticket_reservation_read
        ticket_transfer user_passkey_delete user_passkey_read
        user_passkey_update user_read user_token_delete
        user_token_read
      )a,
    owner: ~w(
        scan_session_read scan_session_update
      )a,
    denied: ~w(
        auth_event_delete auth_event_update check_in_booking_delete
        check_in_booking_update check_in_delete check_in_update
        check_in_vehicle_delete check_in_vehicle_update conduct_violation_delete
        event_update_delete event_update_update ledger_account_delete
        ledger_entry_delete ledger_entry_update ledger_transaction_delete
        ledger_transaction_update merch_order_delete merch_order_item_delete
        merch_shipment_delete message_idempotency_update newsletter_email_event_delete
        newsletter_email_event_update newsletter_unsubscribe_event_delete newsletter_unsubscribe_event_update
        payment_delete payout_delete post_delete
        refund_delete scan_record_delete scan_record_update
        scan_session_delete session_check_in_update signup_application_delete
        signup_application_event_delete signup_application_event_update sms_delivery_receipt_delete
        sms_delivery_receipt_update sms_message_delete sms_message_update
        sms_received_delete sms_received_update ticket_delete
        ticket_order_delete user_delete user_event_delete
        user_event_update user_note_delete user_note_update
        user_token_update webhook_event_update
      )a
  }

  describe "schema coverage" do
    test "every Ecto schema has a policy object or is explicitly excluded" do
      unmapped =
        schema_modules() -- (Map.keys(@schema_objects) ++ @excluded_schemas)

      assert unmapped == [],
             "Schemas without a policy object (add one to the policy and to " <>
               "@schema_objects, or exclude it): #{inspect(unmapped)}"
    end

    test "every mapped schema still exists" do
      stale = Map.keys(@schema_objects) -- schema_modules()
      assert stale == [], "Stale entries in @schema_objects: #{inspect(stale)}"
    end

    test "policy objects match the mapped objects" do
      expected = Enum.sort(Map.values(@schema_objects) ++ @virtual_objects)
      assert policy_objects() == expected
    end

    test "every rule appears in exactly one matrix group" do
      listed = @matrix |> Map.values() |> List.flatten()
      assert listed -- Enum.uniq(listed) == []
      assert Enum.sort(listed) == Enum.sort(rule_names())
    end
  end

  describe "rule matrix" do
    for {group, actions} <- @matrix do
      test "rules classified #{group}" do
        mismatches =
          for action <- unquote(actions),
              (actual = classify(action)) != unquote(group) do
            {action, actual}
          end

        assert mismatches == [],
               "Expected #{unquote(group)} but the policy says: " <>
                 inspect(mismatches)
      end
    end

    test "the classifier tells the owner-only and denied shapes apart" do
      assert classify(:scan_session_read) == :owner
      assert classify(:user_delete) == :denied
    end
  end

  defp schema_modules do
    :ysc
    |> Application.spec(:modules)
    |> Enum.filter(fn module ->
      Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1) and
        module.__schema__(:source) != nil
    end)
    |> Enum.sort()
  end

  defp policy_objects do
    Policy.list_rules() |> Enum.map(& &1.object) |> Enum.uniq() |> Enum.sort()
  end

  defp rule_names, do: Policy.list_rules() |> Enum.map(& &1.name)

  # Evaluates a rule for each kind of caller against somebody else's record,
  # then for the member who owns the record.
  defp classify(action) do
    member = %User{id: Ecto.ULID.generate(), role: :member}
    volunteer = %User{id: Ecto.ULID.generate(), role: :volunteer}
    admin = %User{id: Ecto.ULID.generate(), role: :admin}
    stranger = %{user_id: Ecto.ULID.generate()}
    owned = %{user_id: member.id}

    allowed = fn user, object -> Policy.authorize?(action, user, object) end

    case {allowed.(nil, stranger), allowed.(member, stranger),
          allowed.(volunteer, stranger), allowed.(admin, stranger),
          allowed.(member, owned)} do
      {true, true, true, true, _} -> :public
      {false, true, true, true, _} -> :authenticated
      {false, false, true, true, true} -> :owner_or_staff
      {false, false, true, true, false} -> :staff
      {false, false, false, true, true} -> :owner_or_admin
      {false, false, false, true, false} -> :admin
      {false, false, false, false, true} -> :owner
      {false, false, false, false, false} -> :denied
      other -> {:unexpected, other}
    end
  end
end
