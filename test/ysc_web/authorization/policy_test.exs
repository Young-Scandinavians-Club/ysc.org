defmodule YscWeb.Authorization.PolicyTest do
  @moduledoc """
  Tests for the authorization policy module.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.Authorization.Policy

  describe "post policies" do
    test "admin can create posts" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:post_create, admin)
    end

    test "regular member cannot create posts" do
      member = user_fixture(%{role: "member"})
      assert {:error, :unauthorized} = Policy.authorize(:post_create, member)
    end

    test "anyone can read posts" do
      member = user_fixture(%{role: "member"})
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:post_read, member)
      assert :ok = Policy.authorize(:post_read, admin)
    end

    test "admin can update posts" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:post_update, admin)
    end

    test "regular member cannot update posts" do
      member = user_fixture(%{role: "member"})
      assert {:error, :unauthorized} = Policy.authorize(:post_update, member)
    end

    test "no one can delete posts (always denied)" do
      admin = user_fixture(%{role: "admin"})
      assert {:error, :unauthorized} = Policy.authorize(:post_delete, admin)
    end
  end

  describe "user policies" do
    test "anyone can create users" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:user_create, member)
    end

    test "admin can read any user" do
      admin = user_fixture(%{role: "admin"})
      other_user = user_fixture()

      assert :ok = Policy.authorize(:user_read, admin, other_user)
    end

    # Note: LetMe Policy may require explicit :own_resource check implementation
    # The :own_resource check relies on comparing resource.id with user.id
    # which may not work directly without custom check implementation

    test "member cannot read other users" do
      member = user_fixture(%{role: "member"})
      other_user = user_fixture()

      assert {:error, :unauthorized} =
               Policy.authorize(:user_read, member, other_user)
    end

    test "admin can update any user" do
      admin = user_fixture(%{role: "admin"})
      other_user = user_fixture()

      assert :ok = Policy.authorize(:user_update, admin, other_user)
    end

    # Note: LetMe Policy :own_resource check may require custom implementation

    test "no one can delete users (always denied)" do
      admin = user_fixture(%{role: "admin"})
      assert {:error, :unauthorized} = Policy.authorize(:user_delete, admin)
    end
  end

  describe "event policies" do
    test "admin can create events" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:event_create, admin)
    end

    test "regular member cannot create events" do
      member = user_fixture(%{role: "member"})
      assert {:error, :unauthorized} = Policy.authorize(:event_create, member)
    end

    test "anyone can read events" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:event_read, member)
    end

    test "admin can update events" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:event_update, admin)
    end

    test "admin can delete events" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:event_delete, admin)
    end
  end

  describe "media_image policies" do
    test "admin can create images" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:media_image_create, admin)
    end

    test "member cannot create images" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:media_image_create, member)
    end

    test "anyone can read images" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:media_image_read, member)
    end

    test "admin can update images" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:media_image_update, admin)
    end

    test "admin can delete images" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:media_image_delete, admin)
    end
  end

  describe "site_setting policies" do
    test "admin can manage site settings" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:site_setting_create, admin)
      assert :ok = Policy.authorize(:site_setting_update, admin)
      assert :ok = Policy.authorize(:site_setting_delete, admin)
    end

    test "anyone can read site settings" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:site_setting_read, member)
    end
  end

  describe "agenda policies" do
    test "admin can manage agendas" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:agenda_create, admin)
      assert :ok = Policy.authorize(:agenda_update, admin)
      assert :ok = Policy.authorize(:agenda_delete, admin)
    end

    test "anyone can read agendas" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:agenda_read, member)
    end

    test "member cannot manage agendas" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} = Policy.authorize(:agenda_create, member)
      assert {:error, :unauthorized} = Policy.authorize(:agenda_update, member)
      assert {:error, :unauthorized} = Policy.authorize(:agenda_delete, member)
    end
  end

  describe "agenda_item policies" do
    test "admin can manage agenda items" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:agenda_item_create, admin)
      assert :ok = Policy.authorize(:agenda_item_update, admin)
      assert :ok = Policy.authorize(:agenda_item_delete, admin)
    end

    test "anyone can read agenda items" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:agenda_item_read, member)
    end
  end

  describe "ticket_tier policies" do
    test "admin can manage ticket tiers" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:ticket_tier_create, admin)
      assert :ok = Policy.authorize(:ticket_tier_update, admin)
      assert :ok = Policy.authorize(:ticket_tier_delete, admin)
    end

    test "anyone can read ticket tiers" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:ticket_tier_read, member)
    end

    test "member cannot manage ticket tiers" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:ticket_tier_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:ticket_tier_update, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:ticket_tier_delete, member)
    end
  end

  describe "signup_application policies" do
    test "anyone can create signup applications" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:signup_application_create, member)
    end

    test "admin can read any signup application" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:signup_application_read, admin)
    end

    test "admin can update signup applications" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:signup_application_update, admin)
    end

    test "no one can delete signup applications" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:signup_application_delete, admin)
    end

    test "member cannot update signup applications" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:signup_application_update, member)
    end
  end

  describe "family_invite policies" do
    test "admin can create family invites" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:family_invite_create, admin)
    end

    test "admin can read family invites" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:family_invite_read, admin)
    end

    test "admin can revoke family invites" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:family_invite_revoke, admin)
    end

    test "member cannot create family invites without permission" do
      member = user_fixture(%{role: "member"})
      # Note: :can_send_family_invite check would need custom implementation
      # This tests the basic case without that check
      assert {:error, :unauthorized} =
               Policy.authorize(:family_invite_create, member)
    end
  end

  describe "family_sub_account policies" do
    test "admin can manage family sub-accounts" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:family_sub_account_read, admin)
      assert :ok = Policy.authorize(:family_sub_account_remove, admin)
      assert :ok = Policy.authorize(:family_sub_account_manage, admin)
    end

    test "member cannot read other family sub-accounts" do
      member = user_fixture(%{role: "member"})
      other_user = user_fixture()

      assert {:error, :unauthorized} =
               Policy.authorize(:family_sub_account_read, member, other_user)
    end
  end

  describe "booking policies" do
    test "anyone can create bookings" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:booking_create, member)
    end

    test "admin can read any booking" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:booking_read, admin)
    end

    test "admin can update any booking" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:booking_update, admin)
    end

    test "admin can delete bookings" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:booking_delete, admin)
    end

    test "admin can cancel bookings" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:booking_cancel, admin)
    end

    test "member cannot delete bookings" do
      member = user_fixture(%{role: "member"})
      assert {:error, :unauthorized} = Policy.authorize(:booking_delete, member)
    end
  end

  describe "ticket policies" do
    test "admin can create tickets" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:ticket_create, admin)
    end

    test "admin can read tickets" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:ticket_read, admin)
    end

    test "admin can update tickets" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:ticket_update, admin)
    end

    test "no one can delete tickets" do
      admin = user_fixture(%{role: "admin"})
      assert {:error, :unauthorized} = Policy.authorize(:ticket_delete, admin)
    end

    test "admin can transfer tickets" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:ticket_transfer, admin)
    end

    test "member cannot create tickets" do
      member = user_fixture(%{role: "member"})
      assert {:error, :unauthorized} = Policy.authorize(:ticket_create, member)
    end

    test "member cannot update tickets" do
      member = user_fixture(%{role: "member"})
      assert {:error, :unauthorized} = Policy.authorize(:ticket_update, member)
    end
  end

  describe "ticket_order policies" do
    test "anyone can create ticket orders" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:ticket_order_create, member)
    end

    test "admin can read ticket orders" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:ticket_order_read, admin)
    end

    test "admin can update ticket orders" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:ticket_order_update, admin)
    end

    test "no one can delete ticket orders" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:ticket_order_delete, admin)
    end

    test "admin can cancel ticket orders" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:ticket_order_cancel, admin)
    end
  end

  describe "ticket_detail policies" do
    test "admin can manage ticket details" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:ticket_detail_create, admin)
      assert :ok = Policy.authorize(:ticket_detail_read, admin)
      assert :ok = Policy.authorize(:ticket_detail_update, admin)
      assert :ok = Policy.authorize(:ticket_detail_delete, admin)
    end

    test "member cannot read other ticket details" do
      member = user_fixture(%{role: "member"})
      other_user = user_fixture()

      assert {:error, :unauthorized} =
               Policy.authorize(:ticket_detail_read, member, other_user)
    end
  end

  describe "subscription policies" do
    test "admin can manage subscriptions" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:subscription_create, admin)
      assert :ok = Policy.authorize(:subscription_read, admin)
      assert :ok = Policy.authorize(:subscription_update, admin)
      assert :ok = Policy.authorize(:subscription_delete, admin)
    end

    test "member cannot create subscriptions" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:subscription_create, member)
    end

    test "member cannot update subscriptions" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:subscription_update, member)
    end

    test "member cannot delete subscriptions" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:subscription_delete, member)
    end
  end

  describe "subscription_item policies" do
    test "admin can manage subscription items" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:subscription_item_create, admin)
      assert :ok = Policy.authorize(:subscription_item_read, admin)
      assert :ok = Policy.authorize(:subscription_item_update, admin)
      assert :ok = Policy.authorize(:subscription_item_delete, admin)
    end

    test "member cannot manage subscription items" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:subscription_item_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:subscription_item_update, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:subscription_item_delete, member)
    end
  end

  describe "payment_method policies" do
    test "anyone can create payment methods" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:payment_method_create, member)
    end

    test "admin can read payment methods" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:payment_method_read, admin)
    end

    test "admin can update payment methods" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:payment_method_update, admin)
    end

    test "admin can delete payment methods" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:payment_method_delete, admin)
    end

    test "member cannot read other payment methods" do
      member = user_fixture(%{role: "member"})
      other_user = user_fixture()

      assert {:error, :unauthorized} =
               Policy.authorize(:payment_method_read, member, other_user)
    end
  end

  describe "payment policies" do
    test "admin can create payments" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:payment_create, admin)
    end

    test "admin can read payments" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:payment_read, admin)
    end

    test "admin can update payments" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:payment_update, admin)
    end

    test "no one can delete payments" do
      admin = user_fixture(%{role: "admin"})
      assert {:error, :unauthorized} = Policy.authorize(:payment_delete, admin)
    end

    test "member cannot create payments" do
      member = user_fixture(%{role: "member"})
      assert {:error, :unauthorized} = Policy.authorize(:payment_create, member)
    end

    test "member cannot update payments" do
      member = user_fixture(%{role: "member"})
      assert {:error, :unauthorized} = Policy.authorize(:payment_update, member)
    end
  end

  describe "refund policies" do
    test "admin can create refunds" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:refund_create, admin)
    end

    test "admin can read refunds" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:refund_read, admin)
    end

    test "admin can update refunds" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:refund_update, admin)
    end

    test "no one can delete refunds" do
      admin = user_fixture(%{role: "admin"})
      assert {:error, :unauthorized} = Policy.authorize(:refund_delete, admin)
    end

    test "member cannot create refunds" do
      member = user_fixture(%{role: "member"})
      assert {:error, :unauthorized} = Policy.authorize(:refund_create, member)
    end
  end

  describe "payout policies" do
    test "admin can manage payouts" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:payout_create, admin)
      assert :ok = Policy.authorize(:payout_read, admin)
      assert :ok = Policy.authorize(:payout_update, admin)
    end

    test "no one can delete payouts" do
      admin = user_fixture(%{role: "admin"})
      assert {:error, :unauthorized} = Policy.authorize(:payout_delete, admin)
    end

    test "member cannot access payouts" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} = Policy.authorize(:payout_create, member)
      assert {:error, :unauthorized} = Policy.authorize(:payout_read, member)
      assert {:error, :unauthorized} = Policy.authorize(:payout_update, member)
    end
  end

  describe "expense_report policies" do
    test "anyone can create expense reports" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:expense_report_create, member)
    end

    test "admin can manage expense reports" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:expense_report_read, admin)
      assert :ok = Policy.authorize(:expense_report_update, admin)
      assert :ok = Policy.authorize(:expense_report_delete, admin)
      assert :ok = Policy.authorize(:expense_report_submit, admin)
      assert :ok = Policy.authorize(:expense_report_approve, admin)
      assert :ok = Policy.authorize(:expense_report_reject, admin)
    end

    test "member cannot approve expense reports" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:expense_report_approve, member)
    end

    test "member cannot reject expense reports" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:expense_report_reject, member)
    end

    test "member cannot read other expense reports" do
      member = user_fixture(%{role: "member"})
      other_user = user_fixture()

      assert {:error, :unauthorized} =
               Policy.authorize(:expense_report_read, member, other_user)
    end
  end

  describe "expense_report_item policies" do
    test "admin can manage expense report items" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:expense_report_item_create, admin)
      assert :ok = Policy.authorize(:expense_report_item_read, admin)
      assert :ok = Policy.authorize(:expense_report_item_update, admin)
      assert :ok = Policy.authorize(:expense_report_item_delete, admin)
    end

    test "member cannot manage other expense report items" do
      member = user_fixture(%{role: "member"})
      other_user = user_fixture()

      assert {:error, :unauthorized} =
               Policy.authorize(:expense_report_item_create, member, other_user)

      assert {:error, :unauthorized} =
               Policy.authorize(:expense_report_item_read, member, other_user)
    end
  end

  describe "expense_report_income_item policies" do
    test "admin can manage expense report income items" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:expense_report_income_item_create, admin)
      assert :ok = Policy.authorize(:expense_report_income_item_read, admin)
      assert :ok = Policy.authorize(:expense_report_income_item_update, admin)
      assert :ok = Policy.authorize(:expense_report_income_item_delete, admin)
    end

    test "member cannot manage other expense report income items" do
      member = user_fixture(%{role: "member"})
      other_user = user_fixture()

      assert {:error, :unauthorized} =
               Policy.authorize(
                 :expense_report_income_item_create,
                 member,
                 other_user
               )
    end
  end

  describe "bank_account policies" do
    test "anyone can create bank accounts" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:bank_account_create, member)
    end

    test "admin can manage bank accounts" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:bank_account_read, admin)
      assert :ok = Policy.authorize(:bank_account_update, admin)
      assert :ok = Policy.authorize(:bank_account_delete, admin)
    end

    test "member cannot read other bank accounts" do
      member = user_fixture(%{role: "member"})
      other_user = user_fixture()

      assert {:error, :unauthorized} =
               Policy.authorize(:bank_account_read, member, other_user)
    end
  end

  describe "address policies" do
    test "anyone can create addresses" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:address_create, member)
    end

    test "admin can manage addresses" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:address_read, admin)
      assert :ok = Policy.authorize(:address_update, admin)
      assert :ok = Policy.authorize(:address_delete, admin)
    end

    test "member cannot read other addresses" do
      member = user_fixture(%{role: "member"})
      other_user = user_fixture()

      assert {:error, :unauthorized} =
               Policy.authorize(:address_read, member, other_user)
    end
  end

  describe "family_member policies" do
    test "anyone can create family members" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:family_member_create, member)
    end

    test "admin can manage family members" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:family_member_read, admin)
      assert :ok = Policy.authorize(:family_member_update, admin)
      assert :ok = Policy.authorize(:family_member_delete, admin)
    end

    test "member cannot manage other family members" do
      member = user_fixture(%{role: "member"})
      other_user = user_fixture()

      assert {:error, :unauthorized} =
               Policy.authorize(:family_member_read, member, other_user)

      assert {:error, :unauthorized} =
               Policy.authorize(:family_member_update, member, other_user)
    end
  end

  describe "user_note policies" do
    test "admin can create user notes" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:user_note_create, admin)
    end

    test "admin can read user notes" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:user_note_read, admin)
    end

    test "no one can update user notes" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:user_note_update, admin)
    end

    test "no one can delete user notes" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:user_note_delete, admin)
    end

    test "member cannot create user notes" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:user_note_create, member)
    end

    test "member cannot read user notes" do
      member = user_fixture(%{role: "member"})
      assert {:error, :unauthorized} = Policy.authorize(:user_note_read, member)
    end
  end

  describe "user_event policies" do
    test "admin can create user events" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:user_event_create, admin)
    end

    test "admin can read user events" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:user_event_read, admin)
    end

    test "no one can update user events" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:user_event_update, admin)
    end

    test "no one can delete user events" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:user_event_delete, admin)
    end

    test "member cannot access user events" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:user_event_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:user_event_read, member)
    end
  end

  describe "user_token policies" do
    test "anyone can create user tokens" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:user_token_create, member)
    end

    test "admin can read user tokens" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:user_token_read, admin)
    end

    test "no one can update user tokens" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:user_token_update, admin)
    end

    test "admin can delete user tokens" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:user_token_delete, admin)
    end

    test "member cannot read other user tokens" do
      member = user_fixture(%{role: "member"})
      other_user = user_fixture()

      assert {:error, :unauthorized} =
               Policy.authorize(:user_token_read, member, other_user)
    end
  end

  describe "auth_event policies" do
    test "anyone can create auth events" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:auth_event_create, member)
    end

    test "admin can read auth events" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:auth_event_read, admin)
    end

    test "no one can update auth events" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:auth_event_update, admin)
    end

    test "no one can delete auth events" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:auth_event_delete, admin)
    end

    test "member cannot read other auth events" do
      member = user_fixture(%{role: "member"})
      other_user = user_fixture()

      assert {:error, :unauthorized} =
               Policy.authorize(:auth_event_read, member, other_user)
    end
  end

  describe "signup_application_event policies" do
    test "admin can create signup application events" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:signup_application_event_create, admin)
    end

    test "admin can read signup application events" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:signup_application_event_read, admin)
    end

    test "no one can update signup application events" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:signup_application_event_update, admin)
    end

    test "no one can delete signup application events" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:signup_application_event_delete, admin)
    end

    test "member cannot access signup application events" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:signup_application_event_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:signup_application_event_read, member)
    end
  end

  describe "comment policies" do
    test "anyone can create comments" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:comment_create, member)
    end

    test "anyone can read comments" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:comment_read, member)
    end

    test "admin can update comments" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:comment_update, admin)
    end

    test "admin can delete comments" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:comment_delete, admin)
    end

    test "member cannot update other comments" do
      member = user_fixture(%{role: "member"})
      other_user = user_fixture()

      assert {:error, :unauthorized} =
               Policy.authorize(:comment_update, member, other_user)
    end
  end

  describe "contact_form policies" do
    test "anyone can create contact forms" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:contact_form_create, member)
    end

    test "admin can manage contact forms" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:contact_form_read, admin)
      assert :ok = Policy.authorize(:contact_form_update, admin)
      assert :ok = Policy.authorize(:contact_form_delete, admin)
    end

    test "member cannot read contact forms" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:contact_form_read, member)
    end
  end

  describe "volunteer policies" do
    test "anyone can create volunteer forms" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:volunteer_create, member)
    end

    test "admin can manage volunteer forms" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:volunteer_read, admin)
      assert :ok = Policy.authorize(:volunteer_update, admin)
      assert :ok = Policy.authorize(:volunteer_delete, admin)
    end

    test "member cannot read volunteer forms" do
      member = user_fixture(%{role: "member"})
      assert {:error, :unauthorized} = Policy.authorize(:volunteer_read, member)
    end
  end

  describe "conduct_violation policies" do
    test "anyone can create conduct violations" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:conduct_violation_create, member)
    end

    test "admin can manage conduct violations" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:conduct_violation_read, admin)
      assert :ok = Policy.authorize(:conduct_violation_update, admin)
    end

    test "no one can delete conduct violations" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:conduct_violation_delete, admin)
    end

    test "member cannot read conduct violations" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:conduct_violation_read, member)
    end
  end

  describe "event_faq policies" do
    test "admin can manage event FAQs" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:event_faq_create, admin)
      assert :ok = Policy.authorize(:event_faq_update, admin)
      assert :ok = Policy.authorize(:event_faq_delete, admin)
    end

    test "anyone can read event FAQs" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:event_faq_read, member)
    end

    test "member cannot manage event FAQs" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:event_faq_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:event_faq_update, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:event_faq_delete, member)
    end
  end

  describe "room policies" do
    test "admin can manage rooms" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:room_create, admin)
      assert :ok = Policy.authorize(:room_update, admin)
      assert :ok = Policy.authorize(:room_delete, admin)
    end

    test "anyone can read rooms" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:room_read, member)
    end

    test "member cannot manage rooms" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} = Policy.authorize(:room_create, member)
      assert {:error, :unauthorized} = Policy.authorize(:room_update, member)
      assert {:error, :unauthorized} = Policy.authorize(:room_delete, member)
    end
  end

  describe "room_category policies" do
    test "admin can manage room categories" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:room_category_create, admin)
      assert :ok = Policy.authorize(:room_category_update, admin)
      assert :ok = Policy.authorize(:room_category_delete, admin)
    end

    test "anyone can read room categories" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:room_category_read, member)
    end
  end

  describe "season policies" do
    test "admin can manage seasons" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:season_create, admin)
      assert :ok = Policy.authorize(:season_update, admin)
      assert :ok = Policy.authorize(:season_delete, admin)
    end

    test "anyone can read seasons" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:season_read, member)
    end
  end

  describe "pricing_rule policies" do
    test "admin can manage pricing rules" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:pricing_rule_create, admin)
      assert :ok = Policy.authorize(:pricing_rule_read, admin)
      assert :ok = Policy.authorize(:pricing_rule_update, admin)
      assert :ok = Policy.authorize(:pricing_rule_delete, admin)
    end

    test "member cannot access pricing rules" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:pricing_rule_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:pricing_rule_read, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:pricing_rule_update, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:pricing_rule_delete, member)
    end
  end

  describe "refund_policy policies" do
    test "admin can manage refund policies" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:refund_policy_create, admin)
      assert :ok = Policy.authorize(:refund_policy_update, admin)
      assert :ok = Policy.authorize(:refund_policy_delete, admin)
    end

    test "anyone can read refund policies" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:refund_policy_read, member)
    end
  end

  describe "refund_policy_rule policies" do
    test "admin can manage refund policy rules" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:refund_policy_rule_create, admin)
      assert :ok = Policy.authorize(:refund_policy_rule_read, admin)
      assert :ok = Policy.authorize(:refund_policy_rule_update, admin)
      assert :ok = Policy.authorize(:refund_policy_rule_delete, admin)
    end

    test "member cannot access refund policy rules" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:refund_policy_rule_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:refund_policy_rule_read, member)
    end
  end

  describe "booking_room policies" do
    test "admin can manage booking rooms" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:booking_room_create, admin)
      assert :ok = Policy.authorize(:booking_room_read, admin)
      assert :ok = Policy.authorize(:booking_room_update, admin)
      assert :ok = Policy.authorize(:booking_room_delete, admin)
    end

    test "member cannot access booking rooms" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:booking_room_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:booking_room_read, member)
    end
  end

  describe "room_inventory policies" do
    test "admin can manage room inventory" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:room_inventory_create, admin)
      assert :ok = Policy.authorize(:room_inventory_read, admin)
      assert :ok = Policy.authorize(:room_inventory_update, admin)
      assert :ok = Policy.authorize(:room_inventory_delete, admin)
    end

    test "member cannot access room inventory" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:room_inventory_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:room_inventory_read, member)
    end
  end

  describe "property_inventory policies" do
    test "admin can manage property inventory" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:property_inventory_create, admin)
      assert :ok = Policy.authorize(:property_inventory_read, admin)
      assert :ok = Policy.authorize(:property_inventory_update, admin)
      assert :ok = Policy.authorize(:property_inventory_delete, admin)
    end

    test "member cannot access property inventory" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:property_inventory_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:property_inventory_read, member)
    end
  end

  describe "blackout policies" do
    test "admin can manage blackouts" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:blackout_create, admin)
      assert :ok = Policy.authorize(:blackout_read, admin)
      assert :ok = Policy.authorize(:blackout_update, admin)
      assert :ok = Policy.authorize(:blackout_delete, admin)
    end

    test "member cannot access blackouts" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:blackout_create, member)

      assert {:error, :unauthorized} = Policy.authorize(:blackout_read, member)
    end
  end

  describe "door_code policies" do
    test "admin can manage door codes" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:door_code_create, admin)
      assert :ok = Policy.authorize(:door_code_read, admin)
      assert :ok = Policy.authorize(:door_code_update, admin)
      assert :ok = Policy.authorize(:door_code_delete, admin)
    end

    test "member cannot create door codes" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:door_code_create, member)
    end

    test "member cannot update door codes" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:door_code_update, member)
    end

    test "member cannot delete door codes" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:door_code_delete, member)
    end
  end

  describe "outage_tracker policies" do
    test "admin can manage outage trackers" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:outage_tracker_create, admin)
      assert :ok = Policy.authorize(:outage_tracker_read, admin)
      assert :ok = Policy.authorize(:outage_tracker_update, admin)
      assert :ok = Policy.authorize(:outage_tracker_delete, admin)
    end

    test "member cannot access outage trackers" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:outage_tracker_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:outage_tracker_read, member)
    end
  end

  describe "pending_refund policies" do
    test "admin can manage pending refunds" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:pending_refund_create, admin)
      assert :ok = Policy.authorize(:pending_refund_read, admin)
      assert :ok = Policy.authorize(:pending_refund_update, admin)
      assert :ok = Policy.authorize(:pending_refund_delete, admin)
    end

    test "member cannot access pending refunds" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:pending_refund_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:pending_refund_read, member)
    end
  end

  describe "ledger_entry policies" do
    test "admin can create ledger entries" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:ledger_entry_create, admin)
    end

    test "admin can read ledger entries" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:ledger_entry_read, admin)
    end

    test "no one can update ledger entries" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_entry_update, admin)
    end

    test "no one can delete ledger entries" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_entry_delete, admin)
    end

    test "member cannot access ledger entries" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_entry_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_entry_read, member)
    end
  end

  describe "ledger_account policies" do
    test "admin can manage ledger accounts" do
      admin = user_fixture(%{role: "admin"})

      assert :ok = Policy.authorize(:ledger_account_create, admin)
      assert :ok = Policy.authorize(:ledger_account_read, admin)
      assert :ok = Policy.authorize(:ledger_account_update, admin)
    end

    test "no one can delete ledger accounts" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_account_delete, admin)
    end

    test "member cannot access ledger accounts" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_account_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_account_read, member)
    end
  end

  describe "ledger_transaction policies" do
    test "admin can create ledger transactions" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:ledger_transaction_create, admin)
    end

    test "admin can read ledger transactions" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:ledger_transaction_read, admin)
    end

    test "no one can update ledger transactions" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_transaction_update, admin)
    end

    test "no one can delete ledger transactions" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_transaction_delete, admin)
    end

    test "member cannot access ledger transactions" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_transaction_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_transaction_read, member)
    end
  end

  describe "sms_message policies" do
    test "admin can create sms messages" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:sms_message_create, admin)
    end

    test "admin can read sms messages" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:sms_message_read, admin)
    end

    test "no one can update sms messages" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:sms_message_update, admin)
    end

    test "no one can delete sms messages" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:sms_message_delete, admin)
    end

    test "member cannot create sms messages" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:sms_message_create, member)
    end

    test "member cannot read other sms messages" do
      member = user_fixture(%{role: "member"})
      other_user = user_fixture()

      assert {:error, :unauthorized} =
               Policy.authorize(:sms_message_read, member, other_user)
    end
  end

  describe "sms_received policies" do
    test "anyone can create sms received records" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:sms_received_create, member)
    end

    test "admin can read sms received records" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:sms_received_read, admin)
    end

    test "no one can update sms received records" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:sms_received_update, admin)
    end

    test "no one can delete sms received records" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:sms_received_delete, admin)
    end

    test "member cannot read sms received records" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:sms_received_read, member)
    end
  end

  describe "sms_delivery_receipt policies" do
    test "anyone can create sms delivery receipts" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:sms_delivery_receipt_create, member)
    end

    test "admin can read sms delivery receipts" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:sms_delivery_receipt_read, admin)
    end

    test "no one can update sms delivery receipts" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:sms_delivery_receipt_update, admin)
    end

    test "no one can delete sms delivery receipts" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:sms_delivery_receipt_delete, admin)
    end

    test "member cannot read sms delivery receipts" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:sms_delivery_receipt_read, member)
    end
  end

  describe "message_idempotency policies" do
    test "anyone can create message idempotency records" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:message_idempotency_create, member)
    end

    test "admin can read message idempotency records" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:message_idempotency_read, admin)
    end

    test "no one can update message idempotency records" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:message_idempotency_update, admin)
    end

    test "admin can delete message idempotency records" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:message_idempotency_delete, admin)
    end

    test "member cannot read message idempotency records" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:message_idempotency_read, member)
    end

    test "member cannot delete message idempotency records" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:message_idempotency_delete, member)
    end
  end

  describe "webhook_event policies" do
    test "anyone can create webhook events" do
      member = user_fixture(%{role: "member"})
      assert :ok = Policy.authorize(:webhook_event_create, member)
    end

    test "admin can read webhook events" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:webhook_event_read, admin)
    end

    test "no one can update webhook events" do
      admin = user_fixture(%{role: "admin"})

      assert {:error, :unauthorized} =
               Policy.authorize(:webhook_event_update, admin)
    end

    test "admin can delete webhook events" do
      admin = user_fixture(%{role: "admin"})
      assert :ok = Policy.authorize(:webhook_event_delete, admin)
    end

    test "member cannot read webhook events" do
      member = user_fixture(%{role: "member"})

      assert {:error, :unauthorized} =
               Policy.authorize(:webhook_event_read, member)
    end
  end

  describe "edge cases and nil user" do
    test "nil user is unauthorized for admin-only actions" do
      assert {:error, :unauthorized} = Policy.authorize(:event_create, nil)
      assert {:error, :unauthorized} = Policy.authorize(:post_create, nil)

      assert {:error, :unauthorized} =
               Policy.authorize(:media_image_create, nil)
    end

    test "nil user can perform public read actions" do
      assert :ok = Policy.authorize(:event_read, nil)
      assert :ok = Policy.authorize(:post_read, nil)
      assert :ok = Policy.authorize(:site_setting_read, nil)
    end

    test "nil user can create public resources" do
      assert :ok = Policy.authorize(:user_create, nil)
      assert :ok = Policy.authorize(:booking_create, nil)
      assert :ok = Policy.authorize(:contact_form_create, nil)
    end

    test "nil user cannot perform actions requiring authentication" do
      assert {:error, :unauthorized} = Policy.authorize(:user_update, nil)
      assert {:error, :unauthorized} = Policy.authorize(:booking_update, nil)
    end
  end
end
