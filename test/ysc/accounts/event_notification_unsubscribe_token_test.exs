defmodule Ysc.Accounts.EventNotificationUnsubscribeTokenTest do
  use ExUnit.Case, async: true

  alias Ysc.Accounts.EventNotificationUnsubscribeToken

  describe "sign/1 and verify/1" do
    test "a signed token verifies back to the same user id" do
      token =
        EventNotificationUnsubscribeToken.sign("01ARZ3NDEKTSV4RRFFQ69G5FAV")

      assert EventNotificationUnsubscribeToken.verify(token) ==
               {:ok, "01ARZ3NDEKTSV4RRFFQ69G5FAV"}
    end

    test "a token signed with a different salt is rejected" do
      forged = Phoenix.Token.sign(YscWeb.Endpoint, "some_other_salt", "user-id")

      assert EventNotificationUnsubscribeToken.verify(forged) ==
               {:error, :invalid}
    end

    test "garbage input is rejected" do
      assert EventNotificationUnsubscribeToken.verify("not-a-real-token") ==
               {:error, :invalid}
    end

    test "non-binary input is rejected without crashing" do
      assert EventNotificationUnsubscribeToken.verify(nil) == {:error, :invalid}
      assert EventNotificationUnsubscribeToken.verify(123) == {:error, :invalid}
      assert EventNotificationUnsubscribeToken.verify("") == {:error, :invalid}
    end
  end
end
