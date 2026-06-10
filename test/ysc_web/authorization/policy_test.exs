defmodule YscWeb.Authorization.PolicyTest do
  @moduledoc """
  Tests for the authorization policy module.
  """
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.Authorization.Policy

  describe "post policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        volunteer: user_fixture(%{role: "volunteer"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can create posts", %{admin: admin} do
      assert :ok = Policy.authorize(:post_create, admin)
    end

    test "volunteer can create posts", %{volunteer: volunteer} do
      assert :ok = Policy.authorize(:post_create, volunteer)
    end

    test "regular member cannot create posts", %{member: member} do
      assert {:error, :unauthorized} = Policy.authorize(:post_create, member)
    end

    test "anyone can read posts", %{member: member, admin: admin} do
      assert :ok = Policy.authorize(:post_read, member)
      assert :ok = Policy.authorize(:post_read, admin)
    end

    test "admin can update posts", %{admin: admin} do
      assert :ok = Policy.authorize(:post_update, admin)
    end

    test "volunteer can update posts", %{volunteer: volunteer} do
      assert :ok = Policy.authorize(:post_update, volunteer)
    end

    test "regular member cannot update posts", %{member: member} do
      assert {:error, :unauthorized} = Policy.authorize(:post_update, member)
    end

    test "no one can delete posts (always denied)", %{admin: admin} do
      assert {:error, :unauthorized} = Policy.authorize(:post_delete, admin)
    end
  end

  describe "user policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"}),
        other_user: user_fixture()
      }
    end

    test "anyone can create users", %{member: member} do
      assert :ok = Policy.authorize(:user_create, member)
    end

    test "admin can read any user", %{admin: admin, other_user: other_user} do
      assert :ok = Policy.authorize(:user_read, admin, other_user)
    end

    # Note: LetMe Policy may require explicit :own_resource check implementation
    # The :own_resource check relies on comparing resource.id with user.id
    # which may not work directly without custom check implementation

    test "member cannot read other users", %{
      member: member,
      other_user: other_user
    } do
      assert {:error, :unauthorized} =
               Policy.authorize(:user_read, member, other_user)
    end

    test "admin can update any user", %{admin: admin, other_user: other_user} do
      assert :ok = Policy.authorize(:user_update, admin, other_user)
    end

    # Note: LetMe Policy :own_resource check may require custom implementation

    test "no one can delete users (always denied)", %{admin: admin} do
      assert {:error, :unauthorized} = Policy.authorize(:user_delete, admin)
    end
  end

  describe "event policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can create events", %{admin: admin} do
      assert :ok = Policy.authorize(:event_create, admin)
    end

    test "regular member cannot create events", %{member: member} do
      assert {:error, :unauthorized} = Policy.authorize(:event_create, member)
    end

    test "anyone can read events", %{member: member} do
      assert :ok = Policy.authorize(:event_read, member)
    end

    test "admin can update events", %{admin: admin} do
      assert :ok = Policy.authorize(:event_update, admin)
    end

    test "admin can delete events", %{admin: admin} do
      assert :ok = Policy.authorize(:event_delete, admin)
    end
  end

  describe "media_image policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can create images", %{admin: admin} do
      assert :ok = Policy.authorize(:media_image_create, admin)
    end

    test "member cannot create images", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:media_image_create, member)
    end

    test "anyone can read images", %{member: member} do
      assert :ok = Policy.authorize(:media_image_read, member)
    end

    test "admin can update images", %{admin: admin} do
      assert :ok = Policy.authorize(:media_image_update, admin)
    end

    test "admin can delete images", %{admin: admin} do
      assert :ok = Policy.authorize(:media_image_delete, admin)
    end
  end

  describe "site_setting policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage site settings", %{admin: admin} do
      assert :ok = Policy.authorize(:site_setting_create, admin)
      assert :ok = Policy.authorize(:site_setting_update, admin)
      assert :ok = Policy.authorize(:site_setting_delete, admin)
    end

    test "anyone can read site settings", %{member: member} do
      assert :ok = Policy.authorize(:site_setting_read, member)
    end
  end

  describe "agenda policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage agendas", %{admin: admin} do
      assert :ok = Policy.authorize(:agenda_create, admin)
      assert :ok = Policy.authorize(:agenda_update, admin)
      assert :ok = Policy.authorize(:agenda_delete, admin)
    end

    test "anyone can read agendas", %{member: member} do
      assert :ok = Policy.authorize(:agenda_read, member)
    end

    test "member cannot manage agendas", %{member: member} do
      assert {:error, :unauthorized} = Policy.authorize(:agenda_create, member)
      assert {:error, :unauthorized} = Policy.authorize(:agenda_update, member)
      assert {:error, :unauthorized} = Policy.authorize(:agenda_delete, member)
    end
  end

  describe "agenda_item policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage agenda items", %{admin: admin} do
      assert :ok = Policy.authorize(:agenda_item_create, admin)
      assert :ok = Policy.authorize(:agenda_item_update, admin)
      assert :ok = Policy.authorize(:agenda_item_delete, admin)
    end

    test "anyone can read agenda items", %{member: member} do
      assert :ok = Policy.authorize(:agenda_item_read, member)
    end
  end

  describe "ticket_tier policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage ticket tiers", %{admin: admin} do
      assert :ok = Policy.authorize(:ticket_tier_create, admin)
      assert :ok = Policy.authorize(:ticket_tier_update, admin)
      assert :ok = Policy.authorize(:ticket_tier_delete, admin)
    end

    test "anyone can read ticket tiers", %{member: member} do
      assert :ok = Policy.authorize(:ticket_tier_read, member)
    end

    test "member cannot manage ticket tiers", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:ticket_tier_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:ticket_tier_update, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:ticket_tier_delete, member)
    end
  end

  describe "signup_application policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "anyone can create signup applications", %{member: member} do
      assert :ok = Policy.authorize(:signup_application_create, member)
    end

    test "admin can read any signup application", %{admin: admin} do
      assert :ok = Policy.authorize(:signup_application_read, admin)
    end

    test "admin can update signup applications", %{admin: admin} do
      assert :ok = Policy.authorize(:signup_application_update, admin)
    end

    test "no one can delete signup applications", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:signup_application_delete, admin)
    end

    test "member cannot update signup applications", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:signup_application_update, member)
    end
  end

  describe "family_invite policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can create family invites", %{admin: admin} do
      assert :ok = Policy.authorize(:family_invite_create, admin)
    end

    test "admin can read family invites", %{admin: admin} do
      assert :ok = Policy.authorize(:family_invite_read, admin)
    end

    test "admin can revoke family invites", %{admin: admin} do
      assert :ok = Policy.authorize(:family_invite_revoke, admin)
    end

    test "member cannot create family invites without permission", %{
      member: member
    } do
      # Note: :can_send_family_invite check would need custom implementation
      # This tests the basic case without that check
      assert {:error, :unauthorized} =
               Policy.authorize(:family_invite_create, member)
    end
  end

  describe "family_sub_account policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"}),
        other_user: user_fixture()
      }
    end

    test "admin can manage family sub-accounts", %{admin: admin} do
      assert :ok = Policy.authorize(:family_sub_account_read, admin)
      assert :ok = Policy.authorize(:family_sub_account_remove, admin)
      assert :ok = Policy.authorize(:family_sub_account_manage, admin)
    end

    test "member cannot read other family sub-accounts", %{
      member: member,
      other_user: other_user
    } do
      assert {:error, :unauthorized} =
               Policy.authorize(:family_sub_account_read, member, other_user)
    end
  end

  describe "booking policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "anyone can create bookings", %{member: member} do
      assert :ok = Policy.authorize(:booking_create, member)
    end

    test "admin can read any booking", %{admin: admin} do
      assert :ok = Policy.authorize(:booking_read, admin)
    end

    test "admin can update any booking", %{admin: admin} do
      assert :ok = Policy.authorize(:booking_update, admin)
    end

    test "admin can delete bookings", %{admin: admin} do
      assert :ok = Policy.authorize(:booking_delete, admin)
    end

    test "admin can cancel bookings", %{admin: admin} do
      assert :ok = Policy.authorize(:booking_cancel, admin)
    end

    test "member cannot delete bookings", %{member: member} do
      assert {:error, :unauthorized} = Policy.authorize(:booking_delete, member)
    end
  end

  describe "ticket policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can create tickets", %{admin: admin} do
      assert :ok = Policy.authorize(:ticket_create, admin)
    end

    test "admin can read tickets", %{admin: admin} do
      assert :ok = Policy.authorize(:ticket_read, admin)
    end

    test "admin can update tickets", %{admin: admin} do
      assert :ok = Policy.authorize(:ticket_update, admin)
    end

    test "no one can delete tickets", %{admin: admin} do
      assert {:error, :unauthorized} = Policy.authorize(:ticket_delete, admin)
    end

    test "admin can transfer tickets", %{admin: admin} do
      assert :ok = Policy.authorize(:ticket_transfer, admin)
    end

    test "member cannot create tickets", %{member: member} do
      assert {:error, :unauthorized} = Policy.authorize(:ticket_create, member)
    end

    test "member cannot update tickets", %{member: member} do
      assert {:error, :unauthorized} = Policy.authorize(:ticket_update, member)
    end
  end

  describe "ticket_order policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "anyone can create ticket orders", %{member: member} do
      assert :ok = Policy.authorize(:ticket_order_create, member)
    end

    test "admin can read ticket orders", %{admin: admin} do
      assert :ok = Policy.authorize(:ticket_order_read, admin)
    end

    test "admin can update ticket orders", %{admin: admin} do
      assert :ok = Policy.authorize(:ticket_order_update, admin)
    end

    test "no one can delete ticket orders", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:ticket_order_delete, admin)
    end

    test "admin can cancel ticket orders", %{admin: admin} do
      assert :ok = Policy.authorize(:ticket_order_cancel, admin)
    end
  end

  describe "ticket_detail policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"}),
        other_user: user_fixture()
      }
    end

    test "admin can manage ticket details", %{admin: admin} do
      assert :ok = Policy.authorize(:ticket_detail_create, admin)
      assert :ok = Policy.authorize(:ticket_detail_read, admin)
      assert :ok = Policy.authorize(:ticket_detail_update, admin)
      assert :ok = Policy.authorize(:ticket_detail_delete, admin)
    end

    test "member cannot read other ticket details", %{
      member: member,
      other_user: other_user
    } do
      assert {:error, :unauthorized} =
               Policy.authorize(:ticket_detail_read, member, other_user)
    end
  end

  describe "subscription policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage subscriptions", %{admin: admin} do
      assert :ok = Policy.authorize(:subscription_create, admin)
      assert :ok = Policy.authorize(:subscription_read, admin)
      assert :ok = Policy.authorize(:subscription_update, admin)
      assert :ok = Policy.authorize(:subscription_delete, admin)
    end

    test "member cannot create subscriptions", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:subscription_create, member)
    end

    test "member cannot update subscriptions", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:subscription_update, member)
    end

    test "member cannot delete subscriptions", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:subscription_delete, member)
    end
  end

  describe "subscription_item policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage subscription items", %{admin: admin} do
      assert :ok = Policy.authorize(:subscription_item_create, admin)
      assert :ok = Policy.authorize(:subscription_item_read, admin)
      assert :ok = Policy.authorize(:subscription_item_update, admin)
      assert :ok = Policy.authorize(:subscription_item_delete, admin)
    end

    test "member cannot manage subscription items", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:subscription_item_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:subscription_item_update, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:subscription_item_delete, member)
    end
  end

  describe "payment_method policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"}),
        other_user: user_fixture()
      }
    end

    test "anyone can create payment methods", %{member: member} do
      assert :ok = Policy.authorize(:payment_method_create, member)
    end

    test "admin can read payment methods", %{admin: admin} do
      assert :ok = Policy.authorize(:payment_method_read, admin)
    end

    test "admin can update payment methods", %{admin: admin} do
      assert :ok = Policy.authorize(:payment_method_update, admin)
    end

    test "admin can delete payment methods", %{admin: admin} do
      assert :ok = Policy.authorize(:payment_method_delete, admin)
    end

    test "member cannot read other payment methods", %{
      member: member,
      other_user: other_user
    } do
      assert {:error, :unauthorized} =
               Policy.authorize(:payment_method_read, member, other_user)
    end
  end

  describe "payment policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can create payments", %{admin: admin} do
      assert :ok = Policy.authorize(:payment_create, admin)
    end

    test "admin can read payments", %{admin: admin} do
      assert :ok = Policy.authorize(:payment_read, admin)
    end

    test "admin can update payments", %{admin: admin} do
      assert :ok = Policy.authorize(:payment_update, admin)
    end

    test "no one can delete payments", %{admin: admin} do
      assert {:error, :unauthorized} = Policy.authorize(:payment_delete, admin)
    end

    test "member cannot create payments", %{member: member} do
      assert {:error, :unauthorized} = Policy.authorize(:payment_create, member)
    end

    test "member cannot update payments", %{member: member} do
      assert {:error, :unauthorized} = Policy.authorize(:payment_update, member)
    end
  end

  describe "refund policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can create refunds", %{admin: admin} do
      assert :ok = Policy.authorize(:refund_create, admin)
    end

    test "admin can read refunds", %{admin: admin} do
      assert :ok = Policy.authorize(:refund_read, admin)
    end

    test "admin can update refunds", %{admin: admin} do
      assert :ok = Policy.authorize(:refund_update, admin)
    end

    test "no one can delete refunds", %{admin: admin} do
      assert {:error, :unauthorized} = Policy.authorize(:refund_delete, admin)
    end

    test "member cannot create refunds", %{member: member} do
      assert {:error, :unauthorized} = Policy.authorize(:refund_create, member)
    end
  end

  describe "payout policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage payouts", %{admin: admin} do
      assert :ok = Policy.authorize(:payout_create, admin)
      assert :ok = Policy.authorize(:payout_read, admin)
      assert :ok = Policy.authorize(:payout_update, admin)
    end

    test "no one can delete payouts", %{admin: admin} do
      assert {:error, :unauthorized} = Policy.authorize(:payout_delete, admin)
    end

    test "member cannot access payouts", %{member: member} do
      assert {:error, :unauthorized} = Policy.authorize(:payout_create, member)
      assert {:error, :unauthorized} = Policy.authorize(:payout_read, member)
      assert {:error, :unauthorized} = Policy.authorize(:payout_update, member)
    end
  end

  describe "expense_report policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"}),
        other_user: user_fixture()
      }
    end

    test "anyone can create expense reports", %{member: member} do
      assert :ok = Policy.authorize(:expense_report_create, member)
    end

    test "admin can manage expense reports", %{admin: admin} do
      assert :ok = Policy.authorize(:expense_report_read, admin)
      assert :ok = Policy.authorize(:expense_report_update, admin)
      assert :ok = Policy.authorize(:expense_report_delete, admin)
      assert :ok = Policy.authorize(:expense_report_submit, admin)
      assert :ok = Policy.authorize(:expense_report_approve, admin)
      assert :ok = Policy.authorize(:expense_report_reject, admin)
    end

    test "member cannot approve expense reports", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:expense_report_approve, member)
    end

    test "member cannot reject expense reports", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:expense_report_reject, member)
    end

    test "member cannot read other expense reports", %{
      member: member,
      other_user: other_user
    } do
      assert {:error, :unauthorized} =
               Policy.authorize(:expense_report_read, member, other_user)
    end
  end

  describe "expense_report_item policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"}),
        other_user: user_fixture()
      }
    end

    test "admin can manage expense report items", %{admin: admin} do
      assert :ok = Policy.authorize(:expense_report_item_create, admin)
      assert :ok = Policy.authorize(:expense_report_item_read, admin)
      assert :ok = Policy.authorize(:expense_report_item_update, admin)
      assert :ok = Policy.authorize(:expense_report_item_delete, admin)
    end

    test "member cannot manage other expense report items", %{
      member: member,
      other_user: other_user
    } do
      assert {:error, :unauthorized} =
               Policy.authorize(:expense_report_item_create, member, other_user)

      assert {:error, :unauthorized} =
               Policy.authorize(:expense_report_item_read, member, other_user)
    end
  end

  describe "expense_report_income_item policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"}),
        other_user: user_fixture()
      }
    end

    test "admin can manage expense report income items", %{admin: admin} do
      assert :ok = Policy.authorize(:expense_report_income_item_create, admin)
      assert :ok = Policy.authorize(:expense_report_income_item_read, admin)
      assert :ok = Policy.authorize(:expense_report_income_item_update, admin)
      assert :ok = Policy.authorize(:expense_report_income_item_delete, admin)
    end

    test "member cannot manage other expense report income items", %{
      member: member,
      other_user: other_user
    } do
      assert {:error, :unauthorized} =
               Policy.authorize(
                 :expense_report_income_item_create,
                 member,
                 other_user
               )
    end
  end

  describe "bank_account policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"}),
        other_user: user_fixture()
      }
    end

    test "anyone can create bank accounts", %{member: member} do
      assert :ok = Policy.authorize(:bank_account_create, member)
    end

    test "admin can manage bank accounts", %{admin: admin} do
      assert :ok = Policy.authorize(:bank_account_read, admin)
      assert :ok = Policy.authorize(:bank_account_update, admin)
      assert :ok = Policy.authorize(:bank_account_delete, admin)
    end

    test "member cannot read other bank accounts", %{
      member: member,
      other_user: other_user
    } do
      assert {:error, :unauthorized} =
               Policy.authorize(:bank_account_read, member, other_user)
    end
  end

  describe "address policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"}),
        other_user: user_fixture()
      }
    end

    test "anyone can create addresses", %{member: member} do
      assert :ok = Policy.authorize(:address_create, member)
    end

    test "admin can manage addresses", %{admin: admin} do
      assert :ok = Policy.authorize(:address_read, admin)
      assert :ok = Policy.authorize(:address_update, admin)
      assert :ok = Policy.authorize(:address_delete, admin)
    end

    test "member cannot read other addresses", %{
      member: member,
      other_user: other_user
    } do
      assert {:error, :unauthorized} =
               Policy.authorize(:address_read, member, other_user)
    end
  end

  describe "family_member policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"}),
        other_user: user_fixture()
      }
    end

    test "anyone can create family members", %{member: member} do
      assert :ok = Policy.authorize(:family_member_create, member)
    end

    test "admin can manage family members", %{admin: admin} do
      assert :ok = Policy.authorize(:family_member_read, admin)
      assert :ok = Policy.authorize(:family_member_update, admin)
      assert :ok = Policy.authorize(:family_member_delete, admin)
    end

    test "member cannot manage other family members", %{
      member: member,
      other_user: other_user
    } do
      assert {:error, :unauthorized} =
               Policy.authorize(:family_member_read, member, other_user)

      assert {:error, :unauthorized} =
               Policy.authorize(:family_member_update, member, other_user)
    end
  end

  describe "user_note policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can create user notes", %{admin: admin} do
      assert :ok = Policy.authorize(:user_note_create, admin)
    end

    test "admin can read user notes", %{admin: admin} do
      assert :ok = Policy.authorize(:user_note_read, admin)
    end

    test "no one can update user notes", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:user_note_update, admin)
    end

    test "no one can delete user notes", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:user_note_delete, admin)
    end

    test "member cannot create user notes", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:user_note_create, member)
    end

    test "member cannot read user notes", %{member: member} do
      assert {:error, :unauthorized} = Policy.authorize(:user_note_read, member)
    end
  end

  describe "user_event policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can create user events", %{admin: admin} do
      assert :ok = Policy.authorize(:user_event_create, admin)
    end

    test "admin can read user events", %{admin: admin} do
      assert :ok = Policy.authorize(:user_event_read, admin)
    end

    test "no one can update user events", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:user_event_update, admin)
    end

    test "no one can delete user events", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:user_event_delete, admin)
    end

    test "member cannot access user events", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:user_event_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:user_event_read, member)
    end
  end

  describe "user_token policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"}),
        other_user: user_fixture()
      }
    end

    test "anyone can create user tokens", %{member: member} do
      assert :ok = Policy.authorize(:user_token_create, member)
    end

    test "admin can read user tokens", %{admin: admin} do
      assert :ok = Policy.authorize(:user_token_read, admin)
    end

    test "no one can update user tokens", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:user_token_update, admin)
    end

    test "admin can delete user tokens", %{admin: admin} do
      assert :ok = Policy.authorize(:user_token_delete, admin)
    end

    test "member cannot read other user tokens", %{
      member: member,
      other_user: other_user
    } do
      assert {:error, :unauthorized} =
               Policy.authorize(:user_token_read, member, other_user)
    end
  end

  describe "auth_event policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"}),
        other_user: user_fixture()
      }
    end

    test "anyone can create auth events", %{member: member} do
      assert :ok = Policy.authorize(:auth_event_create, member)
    end

    test "admin can read auth events", %{admin: admin} do
      assert :ok = Policy.authorize(:auth_event_read, admin)
    end

    test "no one can update auth events", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:auth_event_update, admin)
    end

    test "no one can delete auth events", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:auth_event_delete, admin)
    end

    test "member cannot read other auth events", %{
      member: member,
      other_user: other_user
    } do
      assert {:error, :unauthorized} =
               Policy.authorize(:auth_event_read, member, other_user)
    end
  end

  describe "signup_application_event policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can create signup application events", %{admin: admin} do
      assert :ok = Policy.authorize(:signup_application_event_create, admin)
    end

    test "admin can read signup application events", %{admin: admin} do
      assert :ok = Policy.authorize(:signup_application_event_read, admin)
    end

    test "no one can update signup application events", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:signup_application_event_update, admin)
    end

    test "no one can delete signup application events", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:signup_application_event_delete, admin)
    end

    test "member cannot access signup application events", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:signup_application_event_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:signup_application_event_read, member)
    end
  end

  describe "comment policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"}),
        other_user: user_fixture()
      }
    end

    test "anyone can create comments", %{member: member} do
      assert :ok = Policy.authorize(:comment_create, member)
    end

    test "anyone can read comments", %{member: member} do
      assert :ok = Policy.authorize(:comment_read, member)
    end

    test "admin can update comments", %{admin: admin} do
      assert :ok = Policy.authorize(:comment_update, admin)
    end

    test "admin can delete comments", %{admin: admin} do
      assert :ok = Policy.authorize(:comment_delete, admin)
    end

    test "member cannot update other comments", %{
      member: member,
      other_user: other_user
    } do
      assert {:error, :unauthorized} =
               Policy.authorize(:comment_update, member, other_user)
    end
  end

  describe "contact_form policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "anyone can create contact forms", %{member: member} do
      assert :ok = Policy.authorize(:contact_form_create, member)
    end

    test "admin can manage contact forms", %{admin: admin} do
      assert :ok = Policy.authorize(:contact_form_read, admin)
      assert :ok = Policy.authorize(:contact_form_update, admin)
      assert :ok = Policy.authorize(:contact_form_delete, admin)
    end

    test "member cannot read contact forms", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:contact_form_read, member)
    end
  end

  describe "volunteer policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "anyone can create volunteer forms", %{member: member} do
      assert :ok = Policy.authorize(:volunteer_create, member)
    end

    test "admin can manage volunteer forms", %{admin: admin} do
      assert :ok = Policy.authorize(:volunteer_read, admin)
      assert :ok = Policy.authorize(:volunteer_update, admin)
      assert :ok = Policy.authorize(:volunteer_delete, admin)
    end

    test "member cannot read volunteer forms", %{member: member} do
      assert {:error, :unauthorized} = Policy.authorize(:volunteer_read, member)
    end
  end

  describe "conduct_violation policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "anyone can create conduct violations", %{member: member} do
      assert :ok = Policy.authorize(:conduct_violation_create, member)
    end

    test "admin can manage conduct violations", %{admin: admin} do
      assert :ok = Policy.authorize(:conduct_violation_read, admin)
      assert :ok = Policy.authorize(:conduct_violation_update, admin)
    end

    test "no one can delete conduct violations", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:conduct_violation_delete, admin)
    end

    test "member cannot read conduct violations", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:conduct_violation_read, member)
    end
  end

  describe "event_faq policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage event FAQs", %{admin: admin} do
      assert :ok = Policy.authorize(:event_faq_create, admin)
      assert :ok = Policy.authorize(:event_faq_update, admin)
      assert :ok = Policy.authorize(:event_faq_delete, admin)
    end

    test "anyone can read event FAQs", %{member: member} do
      assert :ok = Policy.authorize(:event_faq_read, member)
    end

    test "member cannot manage event FAQs", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:event_faq_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:event_faq_update, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:event_faq_delete, member)
    end
  end

  describe "room policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage rooms", %{admin: admin} do
      assert :ok = Policy.authorize(:room_create, admin)
      assert :ok = Policy.authorize(:room_update, admin)
      assert :ok = Policy.authorize(:room_delete, admin)
    end

    test "anyone can read rooms", %{member: member} do
      assert :ok = Policy.authorize(:room_read, member)
    end

    test "member cannot manage rooms", %{member: member} do
      assert {:error, :unauthorized} = Policy.authorize(:room_create, member)
      assert {:error, :unauthorized} = Policy.authorize(:room_update, member)
      assert {:error, :unauthorized} = Policy.authorize(:room_delete, member)
    end
  end

  describe "room_category policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage room categories", %{admin: admin} do
      assert :ok = Policy.authorize(:room_category_create, admin)
      assert :ok = Policy.authorize(:room_category_update, admin)
      assert :ok = Policy.authorize(:room_category_delete, admin)
    end

    test "anyone can read room categories", %{member: member} do
      assert :ok = Policy.authorize(:room_category_read, member)
    end
  end

  describe "season policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage seasons", %{admin: admin} do
      assert :ok = Policy.authorize(:season_create, admin)
      assert :ok = Policy.authorize(:season_update, admin)
      assert :ok = Policy.authorize(:season_delete, admin)
    end

    test "anyone can read seasons", %{member: member} do
      assert :ok = Policy.authorize(:season_read, member)
    end
  end

  describe "pricing_rule policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage pricing rules", %{admin: admin} do
      assert :ok = Policy.authorize(:pricing_rule_create, admin)
      assert :ok = Policy.authorize(:pricing_rule_read, admin)
      assert :ok = Policy.authorize(:pricing_rule_update, admin)
      assert :ok = Policy.authorize(:pricing_rule_delete, admin)
    end

    test "member cannot access pricing rules", %{member: member} do
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
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage refund policies", %{admin: admin} do
      assert :ok = Policy.authorize(:refund_policy_create, admin)
      assert :ok = Policy.authorize(:refund_policy_update, admin)
      assert :ok = Policy.authorize(:refund_policy_delete, admin)
    end

    test "anyone can read refund policies", %{member: member} do
      assert :ok = Policy.authorize(:refund_policy_read, member)
    end
  end

  describe "refund_policy_rule policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage refund policy rules", %{admin: admin} do
      assert :ok = Policy.authorize(:refund_policy_rule_create, admin)
      assert :ok = Policy.authorize(:refund_policy_rule_read, admin)
      assert :ok = Policy.authorize(:refund_policy_rule_update, admin)
      assert :ok = Policy.authorize(:refund_policy_rule_delete, admin)
    end

    test "member cannot access refund policy rules", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:refund_policy_rule_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:refund_policy_rule_read, member)
    end
  end

  describe "booking_room policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage booking rooms", %{admin: admin} do
      assert :ok = Policy.authorize(:booking_room_create, admin)
      assert :ok = Policy.authorize(:booking_room_read, admin)
      assert :ok = Policy.authorize(:booking_room_update, admin)
      assert :ok = Policy.authorize(:booking_room_delete, admin)
    end

    test "member cannot access booking rooms", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:booking_room_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:booking_room_read, member)
    end
  end

  describe "room_inventory policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage room inventory", %{admin: admin} do
      assert :ok = Policy.authorize(:room_inventory_create, admin)
      assert :ok = Policy.authorize(:room_inventory_read, admin)
      assert :ok = Policy.authorize(:room_inventory_update, admin)
      assert :ok = Policy.authorize(:room_inventory_delete, admin)
    end

    test "member cannot access room inventory", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:room_inventory_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:room_inventory_read, member)
    end
  end

  describe "property_inventory policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage property inventory", %{admin: admin} do
      assert :ok = Policy.authorize(:property_inventory_create, admin)
      assert :ok = Policy.authorize(:property_inventory_read, admin)
      assert :ok = Policy.authorize(:property_inventory_update, admin)
      assert :ok = Policy.authorize(:property_inventory_delete, admin)
    end

    test "member cannot access property inventory", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:property_inventory_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:property_inventory_read, member)
    end
  end

  describe "blackout policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage blackouts", %{admin: admin} do
      assert :ok = Policy.authorize(:blackout_create, admin)
      assert :ok = Policy.authorize(:blackout_read, admin)
      assert :ok = Policy.authorize(:blackout_update, admin)
      assert :ok = Policy.authorize(:blackout_delete, admin)
    end

    test "member cannot access blackouts", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:blackout_create, member)

      assert {:error, :unauthorized} = Policy.authorize(:blackout_read, member)
    end
  end

  describe "door_code policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage door codes", %{admin: admin} do
      assert :ok = Policy.authorize(:door_code_create, admin)
      assert :ok = Policy.authorize(:door_code_read, admin)
      assert :ok = Policy.authorize(:door_code_update, admin)
      assert :ok = Policy.authorize(:door_code_delete, admin)
    end

    test "member cannot create door codes", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:door_code_create, member)
    end

    test "member cannot update door codes", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:door_code_update, member)
    end

    test "member cannot delete door codes", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:door_code_delete, member)
    end
  end

  describe "outage_tracker policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage outage trackers", %{admin: admin} do
      assert :ok = Policy.authorize(:outage_tracker_create, admin)
      assert :ok = Policy.authorize(:outage_tracker_read, admin)
      assert :ok = Policy.authorize(:outage_tracker_update, admin)
      assert :ok = Policy.authorize(:outage_tracker_delete, admin)
    end

    test "member cannot access outage trackers", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:outage_tracker_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:outage_tracker_read, member)
    end
  end

  describe "pending_refund policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage pending refunds", %{admin: admin} do
      assert :ok = Policy.authorize(:pending_refund_create, admin)
      assert :ok = Policy.authorize(:pending_refund_read, admin)
      assert :ok = Policy.authorize(:pending_refund_update, admin)
      assert :ok = Policy.authorize(:pending_refund_delete, admin)
    end

    test "member cannot access pending refunds", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:pending_refund_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:pending_refund_read, member)
    end
  end

  describe "ledger_entry policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can create ledger entries", %{admin: admin} do
      assert :ok = Policy.authorize(:ledger_entry_create, admin)
    end

    test "admin can read ledger entries", %{admin: admin} do
      assert :ok = Policy.authorize(:ledger_entry_read, admin)
    end

    test "no one can update ledger entries", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_entry_update, admin)
    end

    test "no one can delete ledger entries", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_entry_delete, admin)
    end

    test "member cannot access ledger entries", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_entry_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_entry_read, member)
    end
  end

  describe "ledger_account policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can manage ledger accounts", %{admin: admin} do
      assert :ok = Policy.authorize(:ledger_account_create, admin)
      assert :ok = Policy.authorize(:ledger_account_read, admin)
      assert :ok = Policy.authorize(:ledger_account_update, admin)
    end

    test "no one can delete ledger accounts", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_account_delete, admin)
    end

    test "member cannot access ledger accounts", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_account_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_account_read, member)
    end
  end

  describe "ledger_transaction policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "admin can create ledger transactions", %{admin: admin} do
      assert :ok = Policy.authorize(:ledger_transaction_create, admin)
    end

    test "admin can read ledger transactions", %{admin: admin} do
      assert :ok = Policy.authorize(:ledger_transaction_read, admin)
    end

    test "no one can update ledger transactions", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_transaction_update, admin)
    end

    test "no one can delete ledger transactions", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_transaction_delete, admin)
    end

    test "member cannot access ledger transactions", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_transaction_create, member)

      assert {:error, :unauthorized} =
               Policy.authorize(:ledger_transaction_read, member)
    end
  end

  describe "sms_message policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"}),
        other_user: user_fixture()
      }
    end

    test "admin can create sms messages", %{admin: admin} do
      assert :ok = Policy.authorize(:sms_message_create, admin)
    end

    test "admin can read sms messages", %{admin: admin} do
      assert :ok = Policy.authorize(:sms_message_read, admin)
    end

    test "no one can update sms messages", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:sms_message_update, admin)
    end

    test "no one can delete sms messages", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:sms_message_delete, admin)
    end

    test "member cannot create sms messages", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:sms_message_create, member)
    end

    test "member cannot read other sms messages", %{
      member: member,
      other_user: other_user
    } do
      assert {:error, :unauthorized} =
               Policy.authorize(:sms_message_read, member, other_user)
    end
  end

  describe "sms_received policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "anyone can create sms received records", %{member: member} do
      assert :ok = Policy.authorize(:sms_received_create, member)
    end

    test "admin can read sms received records", %{admin: admin} do
      assert :ok = Policy.authorize(:sms_received_read, admin)
    end

    test "no one can update sms received records", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:sms_received_update, admin)
    end

    test "no one can delete sms received records", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:sms_received_delete, admin)
    end

    test "member cannot read sms received records", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:sms_received_read, member)
    end
  end

  describe "sms_delivery_receipt policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "anyone can create sms delivery receipts", %{member: member} do
      assert :ok = Policy.authorize(:sms_delivery_receipt_create, member)
    end

    test "admin can read sms delivery receipts", %{admin: admin} do
      assert :ok = Policy.authorize(:sms_delivery_receipt_read, admin)
    end

    test "no one can update sms delivery receipts", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:sms_delivery_receipt_update, admin)
    end

    test "no one can delete sms delivery receipts", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:sms_delivery_receipt_delete, admin)
    end

    test "member cannot read sms delivery receipts", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:sms_delivery_receipt_read, member)
    end
  end

  describe "message_idempotency policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "anyone can create message idempotency records", %{member: member} do
      assert :ok = Policy.authorize(:message_idempotency_create, member)
    end

    test "admin can read message idempotency records", %{admin: admin} do
      assert :ok = Policy.authorize(:message_idempotency_read, admin)
    end

    test "no one can update message idempotency records", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:message_idempotency_update, admin)
    end

    test "admin can delete message idempotency records", %{admin: admin} do
      assert :ok = Policy.authorize(:message_idempotency_delete, admin)
    end

    test "member cannot read message idempotency records", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:message_idempotency_read, member)
    end

    test "member cannot delete message idempotency records", %{member: member} do
      assert {:error, :unauthorized} =
               Policy.authorize(:message_idempotency_delete, member)
    end
  end

  describe "webhook_event policies" do
    setup do
      %{
        admin: user_fixture(%{role: "admin"}),
        member: user_fixture(%{role: "member"})
      }
    end

    test "anyone can create webhook events", %{member: member} do
      assert :ok = Policy.authorize(:webhook_event_create, member)
    end

    test "admin can read webhook events", %{admin: admin} do
      assert :ok = Policy.authorize(:webhook_event_read, admin)
    end

    test "no one can update webhook events", %{admin: admin} do
      assert {:error, :unauthorized} =
               Policy.authorize(:webhook_event_update, admin)
    end

    test "admin can delete webhook events", %{admin: admin} do
      assert :ok = Policy.authorize(:webhook_event_delete, admin)
    end

    test "member cannot read webhook events", %{member: member} do
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
