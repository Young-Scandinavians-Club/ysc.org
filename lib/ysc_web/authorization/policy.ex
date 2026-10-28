defmodule YscWeb.Authorization.Policy do
  @moduledoc """
  Authorization policy definitions.

  Defines access control for resources and actions using LetMe. Call it with
  `Policy.authorize(:object_action, current_user, object)`.

  ## Roles

    * `:admin` - full admin. Money, users, memberships, bookings, merch and
      site settings.
    * `:volunteer` - runs content and events: posts, newsletters, the media
      library, event editing, messaging ticket holders, door check-in and
      attendee details. No access to the money, user, membership, booking
      or merch admin pages.
    * `:member` / anonymous - own data only, plus public reads.

  ## Rule letters

    * `allow role: :admin` / `allow role: :volunteer` - role based.
    * `allow :own_resource` - the object belongs to the user (see
      `YscWeb.Authorization.Policy.Checks`).
    * `allow :authenticated` - any signed-in user. Use this rather than
      `allow true`, which also admits anonymous callers (`nil`).
    * `allow true` - anyone, including anonymous. Only for public reads and
      public forms, and for records written by token- or signature-
      authenticated flows (webhooks, kiosk API, unsubscribe links).
    * `deny true` - never, for any caller.

  ## What this policy cannot express

  Rules see the subject and object but not record state, so "public reads"
  of posts and events rely on the context to hide unpublished rows. Where a
  role limit depends on state, the context picks the action from the state
  (`Events.delete_event/2` asks for `:event_delete_draft` on a draft and
  `:event_delete` on a scheduled event); the cabin door-code window is
  enforced where the booking is loaded.

  ## Calling it

  Use `YscWeb.Authorization` (`can?/3`, `authorize/3`) rather than calling
  this module directly. It accepts a user or a role atom, and `:system` for
  trusted internal callers. `:admin_panel_access` / `:admin_panel_manage`
  guard the admin area itself.

  ## Keeping it current

  `test/ysc_web/authorization/policy_matrix_test.exs` fails when a schema has
  no object here, when an object has no schema, and when any rule's
  outcome per role changes. Add the schema to its schema map and the rule
  to its matrix in the same change. Secrets that are never exposed through a
  policy (`Ysc.OAuth.AuthCode`, `Ysc.VerificationCode`) are listed as
  excluded in that test.
  """
  use LetMe.Policy

  # ---------------------------------------------------------------------------
  # Content
  # ---------------------------------------------------------------------------

  # Volunteers write news; they cannot delete (drafts are soft-deleted
  # through `:post_update`). Reads are public; the context hides unpublished posts.
  object :post do
    action :create do
      allow role: :admin
      allow role: :volunteer
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
      allow role: :volunteer
    end

    action :delete do
      deny true
    end
  end

  object :media_image do
    action :create do
      allow role: :admin
      allow role: :volunteer
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
      allow role: :volunteer
    end

    action :delete do
      allow role: :admin
      allow role: :volunteer
    end
  end

  object :site_setting do
    action :create do
      allow role: :admin
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :comment do
    action :create do
      allow :authenticated
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
      allow :own_resource
    end

    action :delete do
      allow role: :admin
      allow :own_resource
    end
  end

  # ---------------------------------------------------------------------------
  # Admin area
  # ---------------------------------------------------------------------------

  # Virtual object for the admin area itself. `access` is the staff door
  # (admin and volunteer); `manage` is the full-admin-only sections (users,
  # money, memberships, bookings, merch, settings) and the revenue widgets.
  object :admin_panel do
    action :access do
      allow role: :admin
      allow role: :volunteer
    end

    action :manage do
      allow role: :admin
    end
  end

  # ---------------------------------------------------------------------------
  # Accounts
  # ---------------------------------------------------------------------------

  # `:own_resource` lets a member read their own record. `:user_update` is
  # admin-only on purpose: its changeset can set role, state, board position and
  # Stripe ids. Members edit their profile through `User.profile_changeset/3`.
  object :user do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      deny true
    end

    action :impersonate do
      allow role: :admin
    end
  end

  object :signup_application do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      deny true
    end
  end

  object :signup_application_event do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      deny true
    end

    action :delete do
      deny true
    end
  end

  object :user_note do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      deny true
    end

    action :delete do
      deny true
    end
  end

  object :user_event do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      deny true
    end

    action :delete do
      deny true
    end
  end

  object :user_token do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      deny true
    end

    action :delete do
      allow role: :admin
      allow :own_resource
    end
  end

  object :auth_event do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      deny true
    end

    action :delete do
      deny true
    end
  end

  object :user_passkey do
    action :create do
      allow :authenticated
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
      allow :own_resource
    end

    action :delete do
      allow role: :admin
      allow :own_resource
    end
  end

  # Avatars show on public pages (board, authors).
  object :avatar do
    action :create do
      allow :authenticated
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
      allow :own_resource
    end

    action :delete do
      allow role: :admin
      allow :own_resource
    end
  end

  # Board roster is public.
  object :board_position do
    action :create do
      allow role: :admin
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :family_invite do
    action :create do
      allow role: :admin
      allow :can_send_family_invite
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :revoke do
      allow role: :admin
      allow :own_resource
    end
  end

  # Virtual object: a `User` with `primary_user_id` set. There is no table.
  object :family_sub_account do
    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :remove do
      allow role: :admin
      allow :own_resource
    end

    action :manage do
      allow role: :admin
      allow :own_resource
    end
  end

  object :family_member do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
      allow :own_resource
    end

    action :delete do
      allow role: :admin
      allow :own_resource
    end
  end

  object :address do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
      allow :own_resource
    end

    action :delete do
      allow role: :admin
      allow :own_resource
    end
  end

  # ---------------------------------------------------------------------------
  # Events and tickets
  # ---------------------------------------------------------------------------

  # Volunteers create, edit and publish events, and may delete drafts
  # (`delete_draft`). Unpublishing, cancelling and deleting scheduled events
  # are admin-only. `Events` picks `delete_draft` or `delete` from the event's
  # state. Reads are public; the context hides unpublished events.
  object :event do
    action :create do
      allow role: :admin
      allow role: :volunteer
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
      allow role: :volunteer
    end

    action :delete do
      allow role: :admin
    end

    action :publish do
      allow role: :admin
      allow role: :volunteer
    end

    action :unpublish do
      allow role: :admin
    end

    action :cancel do
      allow role: :admin
    end

    action :delete_draft do
      allow role: :admin
      allow role: :volunteer
    end
  end

  # Edited through the event editor, so it follows `:event`.
  object :faq_question do
    action :create do
      allow role: :admin
      allow role: :volunteer
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
      allow role: :volunteer
    end

    action :delete do
      allow role: :admin
      allow role: :volunteer
    end
  end

  object :agenda do
    action :create do
      allow role: :admin
      allow role: :volunteer
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
      allow role: :volunteer
    end

    action :delete do
      allow role: :admin
      allow role: :volunteer
    end
  end

  object :agenda_item do
    action :create do
      allow role: :admin
      allow role: :volunteer
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
      allow role: :volunteer
    end

    action :delete do
      allow role: :admin
      allow role: :volunteer
    end
  end

  # Messages sent to ticket holders. Volunteers host events and need to
  # contact attendees. Updates are immutable once sent.
  object :event_update do
    action :create do
      allow role: :admin
      allow role: :volunteer
    end

    action :read do
      allow role: :admin
      allow role: :volunteer
    end

    action :update do
      deny true
    end

    action :delete do
      deny true
    end
  end

  # Members opt in to event emails; unsubscribe links work by token.
  object :event_notification_subscription do
    action :create do
      allow :authenticated
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
      allow :own_resource
    end

    action :delete do
      allow role: :admin
      allow :own_resource
    end
  end

  object :event_photos_collection do
    action :create do
      allow role: :admin
    end

    action :read do
      allow :authenticated
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  # Volunteers can read tiers but not change prices or capacity.
  object :ticket_tier do
    action :create do
      allow role: :admin
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  # Volunteers read tickets and check attendees in. Grants, reassignment and
  # refunds are admin-only.
  object :ticket do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
      allow role: :volunteer
      allow :own_resource
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      deny true
    end

    action :transfer do
      allow role: :admin
      allow :own_resource
    end
  end

  # Volunteers read orders to check in a whole order.
  object :ticket_order do
    action :create do
      allow :authenticated
    end

    action :read do
      allow role: :admin
      allow role: :volunteer
      allow :own_resource
    end

    action :update do
      allow role: :admin
      allow :own_resource
    end

    action :delete do
      deny true
    end

    action :cancel do
      allow role: :admin
      allow :own_resource
    end
  end

  # Attendee registration answers. Volunteers correct them at the door. It
  # has no owner column: pass `%{user_id: ticket.user_id}` for `:own_resource`.
  object :ticket_detail do
    action :create do
      allow role: :admin
      allow role: :volunteer
      allow :own_resource
    end

    action :read do
      allow role: :admin
      allow role: :volunteer
      allow :own_resource
    end

    action :update do
      allow role: :admin
      allow role: :volunteer
      allow :own_resource
    end

    action :delete do
      allow role: :admin
    end
  end

  # Admin-only to hold or release; the beneficiary can read their own.
  object :ticket_reservation do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  # ---------------------------------------------------------------------------
  # Check-in and scanning
  # ---------------------------------------------------------------------------

  # Sessions are private to the operator who started them, except open
  # membership check-in desks, which any staff member may join; `Scanning`
  # enforces that exception.
  object :scan_session do
    action :create do
      allow role: :admin
      allow role: :volunteer
    end

    action :read do
      allow :own_resource
    end

    action :update do
      allow :own_resource
    end

    action :delete do
      deny true
    end
  end

  # Written while scanning at the door.
  object :scan_record do
    action :create do
      allow role: :admin
      allow role: :volunteer
    end

    action :read do
      allow role: :admin
      allow role: :volunteer
    end

    action :update do
      deny true
    end

    action :delete do
      deny true
    end
  end

  # Membership desk check-ins; undoing one deletes the row.
  object :session_check_in do
    action :create do
      allow role: :admin
      allow role: :volunteer
    end

    action :read do
      allow role: :admin
      allow role: :volunteer
    end

    action :update do
      deny true
    end

    action :delete do
      allow role: :admin
      allow role: :volunteer
    end
  end

  # ---------------------------------------------------------------------------
  # Cabin bookings
  # ---------------------------------------------------------------------------

  object :booking do
    action :create do
      allow :authenticated
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
      allow :own_resource
    end

    action :delete do
      allow role: :admin
    end

    action :cancel do
      allow role: :admin
      allow :own_resource
    end
  end

  # No owner column: pass `%{user_id: booking.user_id}` for `:own_resource`.
  object :booking_guest do
    action :create do
      allow :authenticated
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
      allow :own_resource
    end

    action :delete do
      allow role: :admin
      allow :own_resource
    end
  end

  object :booking_entitlement do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :room do
    action :create do
      allow role: :admin
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :room_category do
    action :create do
      allow role: :admin
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :season do
    action :create do
      allow role: :admin
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :pricing_rule do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :refund_policy do
    action :create do
      allow role: :admin
    end

    action :read do
      allow true
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :refund_policy_rule do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :booking_room do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :room_inventory do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :property_inventory do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :blackout do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  # Time-gated by the stay (shown only once the stay is complete) in the
  # booking views, not here.
  object :door_code do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :outage_tracker do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :pending_refund do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  # Written by the property kiosk API, which authenticates by shared secret.
  object :check_in do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
    end

    action :update do
      deny true
    end

    action :delete do
      deny true
    end
  end

  # Written by the property kiosk API, which authenticates by shared secret.
  object :check_in_booking do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
    end

    action :update do
      deny true
    end

    action :delete do
      deny true
    end
  end

  # Written by the property kiosk API, which authenticates by shared secret.
  object :check_in_vehicle do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
    end

    action :update do
      deny true
    end

    action :delete do
      deny true
    end
  end

  # ---------------------------------------------------------------------------
  # Money
  # ---------------------------------------------------------------------------

  object :subscription do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :subscription_item do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :payment_method do
    action :create do
      allow :authenticated
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
      allow :own_resource
    end

    action :delete do
      allow role: :admin
      allow :own_resource
    end
  end

  object :payment do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      deny true
    end
  end

  object :refund do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      deny true
    end
  end

  object :payout do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      deny true
    end
  end

  object :expense_report do
    action :create do
      allow :authenticated
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
      allow :own_resource
    end

    action :delete do
      allow role: :admin
      allow :own_resource
    end

    action :submit do
      allow role: :admin
      allow :own_resource
    end

    action :approve do
      allow role: :admin
    end

    action :reject do
      allow role: :admin
    end
  end

  # No owner column: pass `%{user_id: report.user_id}` for `:own_resource`.
  object :expense_report_item do
    action :create do
      allow role: :admin
      allow :own_resource
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
      allow :own_resource
    end

    action :delete do
      allow role: :admin
      allow :own_resource
    end
  end

  # No owner column: pass `%{user_id: report.user_id}` for `:own_resource`.
  object :expense_report_income_item do
    action :create do
      allow role: :admin
      allow :own_resource
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
      allow :own_resource
    end

    action :delete do
      allow role: :admin
      allow :own_resource
    end
  end

  object :bank_account do
    action :create do
      allow :authenticated
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
      allow :own_resource
    end

    action :delete do
      allow role: :admin
      allow :own_resource
    end
  end

  object :ledger_entry do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      deny true
    end

    action :delete do
      deny true
    end
  end

  object :ledger_account do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      deny true
    end
  end

  object :ledger_transaction do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      deny true
    end

    action :delete do
      deny true
    end
  end

  # ---------------------------------------------------------------------------
  # Newsletter
  # ---------------------------------------------------------------------------

  # Volunteers have full control of newsletters, including sending.
  object :newsletter_edition do
    action :create do
      allow role: :admin
      allow role: :volunteer
    end

    action :read do
      allow role: :admin
      allow role: :volunteer
    end

    action :update do
      allow role: :admin
      allow role: :volunteer
    end

    action :delete do
      allow role: :admin
      allow role: :volunteer
    end
  end

  # Volunteers have full control of newsletters.
  object :newsletter_notice do
    action :create do
      allow role: :admin
      allow role: :volunteer
    end

    action :read do
      allow role: :admin
      allow role: :volunteer
    end

    action :update do
      allow role: :admin
      allow role: :volunteer
    end

    action :delete do
      allow role: :admin
      allow role: :volunteer
    end
  end

  # Public sign-up (double opt-in). Volunteers manage the list.
  object :newsletter_subscriber do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
      allow role: :volunteer
    end

    action :update do
      allow role: :admin
      allow role: :volunteer
    end

    action :delete do
      allow role: :admin
      allow role: :volunteer
    end
  end

  # Written by the email provider webhook.
  object :newsletter_email_event do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
      allow role: :volunteer
    end

    action :update do
      deny true
    end

    action :delete do
      deny true
    end
  end

  # Written by the unsubscribe link, which authenticates by token.
  object :newsletter_unsubscribe_event do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
      allow role: :volunteer
    end

    action :update do
      deny true
    end

    action :delete do
      deny true
    end
  end

  # ---------------------------------------------------------------------------
  # Merch
  # ---------------------------------------------------------------------------

  # The shop requires sign-in. Catalog sync is admin-only.
  object :merch_product do
    action :create do
      allow role: :admin
    end

    action :read do
      allow :authenticated
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :merch_variant do
    action :create do
      allow role: :admin
    end

    action :read do
      allow :authenticated
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :merch_product_image do
    action :create do
      allow role: :admin
    end

    action :read do
      allow :authenticated
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  # Placing an order needs an account. Items and shipments have no owner
  # column: pass `%{user_id: order.user_id}` for `:own_resource`.
  object :merch_order do
    action :create do
      allow :authenticated
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      deny true
    end

    action :comp do
      allow role: :admin
    end
  end

  object :merch_order_item do
    action :create do
      allow :authenticated
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      deny true
    end
  end

  object :merch_shipment do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      deny true
    end
  end

  object :merch_cart_item do
    action :create do
      allow :authenticated
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      allow role: :admin
      allow :own_resource
    end

    action :delete do
      allow role: :admin
      allow :own_resource
    end
  end

  # ---------------------------------------------------------------------------
  # Forms and messaging
  # ---------------------------------------------------------------------------

  # Public form submissions.
  object :contact_form do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  # The public "volunteer with us" form submission, not the `:volunteer` role.
  object :volunteer do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  # Public report form submissions.
  object :conduct_violation do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      deny true
    end
  end

  object :sms_message do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
      allow :own_resource
    end

    action :update do
      deny true
    end

    action :delete do
      deny true
    end
  end

  # Written by the Flowroute webhook, which authenticates by secret path.
  object :sms_received do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
    end

    action :update do
      deny true
    end

    action :delete do
      deny true
    end
  end

  # Written by the Flowroute webhook, which authenticates by secret path.
  object :sms_delivery_receipt do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
    end

    action :update do
      deny true
    end

    action :delete do
      deny true
    end
  end

  # Written by the notification pipeline.
  object :message_idempotency do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
    end

    action :update do
      deny true
    end

    action :delete do
      allow role: :admin
    end
  end

  # Written by provider webhooks, which authenticate by signature.
  object :webhook_event do
    action :create do
      allow true
    end

    action :read do
      allow role: :admin
    end

    action :update do
      deny true
    end

    action :delete do
      allow role: :admin
    end
  end

  # ---------------------------------------------------------------------------
  # Integrations
  # ---------------------------------------------------------------------------

  # Full-admin integration (OAuth tokens).
  object :google_photos_connection do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :google_photos_poster_album do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end

  object :google_photos_poster_item do
    action :create do
      allow role: :admin
    end

    action :read do
      allow role: :admin
    end

    action :update do
      allow role: :admin
    end

    action :delete do
      allow role: :admin
    end
  end
end
