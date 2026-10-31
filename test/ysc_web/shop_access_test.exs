defmodule YscWeb.ShopAccessTest do
  @moduledoc """
  Isolated buy-gate for the merch shop.

  Anyone may browse after #1764. Cart, checkout, and add-to-cart still go
  through `member_access?/2`. LiveView covers visitor/member/admin pages;
  these cases lock volunteer vs admin and a missing membership flag.
  """
  use ExUnit.Case, async: true

  alias YscWeb.ShopAccess

  describe "member_access?/2" do
    test "visitors cannot buy, even if a membership flag is true" do
      refute ShopAccess.member_access?(nil, true)
      refute ShopAccess.member_access?(nil, false)
      refute ShopAccess.member_access?(nil, nil)
    end

    test "admins can buy without an active membership" do
      admin = %{role: :admin}

      assert ShopAccess.member_access?(admin, false)
      assert ShopAccess.member_access?(admin, nil)
      assert ShopAccess.member_access?(admin, true)
    end

    test "volunteers follow membership and do not get the admin bypass" do
      volunteer = %{role: :volunteer}

      refute ShopAccess.member_access?(volunteer, false)
      refute ShopAccess.member_access?(volunteer, nil)
      assert ShopAccess.member_access?(volunteer, true)
    end

    test "regular users need an explicit true membership flag" do
      user = %{role: :user}

      refute ShopAccess.member_access?(user, nil)
      refute ShopAccess.member_access?(user, false)
      assert ShopAccess.member_access?(user, true)
    end
  end
end
