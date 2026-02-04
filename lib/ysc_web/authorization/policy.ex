defmodule YscWeb.Authorization.Policy do
  @moduledoc """
  Authorization policy definitions.

  Defines access control policies for various resources and actions using LetMe.
  """
  use LetMe.Policy

  object :post do
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
      deny true
    end
  end

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
      allow :own_resource
    end

    action :delete do
      deny true
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

  object :media_image do
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

  object :event do
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

  object :agenda do
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

  object :agenda_item do
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

  object :booking do
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
    end

    action :cancel do
      allow role: :admin
      allow :own_resource
    end
  end

  object :ticket do
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

    action :transfer do
      allow role: :admin
      allow :own_resource
    end
  end

  object :ticket_order do
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
      deny true
    end

    action :cancel do
      allow role: :admin
      allow :own_resource
    end
  end

  object :ticket_detail do
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
    end
  end

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

  object :comment do
    action :create do
      allow true
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

  object :event_faq do
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
end
