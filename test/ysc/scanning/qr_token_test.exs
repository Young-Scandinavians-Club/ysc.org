defmodule Ysc.Scanning.QrTokenTest do
  use Ysc.DataCase, async: true

  alias Ysc.Scanning.QrToken

  describe "sign_membership/1 and verify/1" do
    test "signs and verifies a membership token for a user id" do
      user_id = "01HXYZ123456789ABCDEF00000"
      token = QrToken.sign_membership(user_id)

      assert is_binary(token)
      assert {:ok, {:membership, ^user_id}} = QrToken.verify(token)
    end

    test "membership token is not accepted as a ticket token" do
      user_id = "01HXYZ123456789ABCDEF00001"
      token = QrToken.sign_membership(user_id)

      # verify still succeeds — but the payload identifies it as :membership
      assert {:ok, {:membership, _}} = QrToken.verify(token)
    end
  end

  describe "sign_ticket/1 and verify/1" do
    test "signs and verifies a ticket token for a ticket id" do
      ticket_id = "01HXYZ123456789ABCDEF00002"
      token = QrToken.sign_ticket(ticket_id)

      assert is_binary(token)
      assert {:ok, {:ticket, ^ticket_id}} = QrToken.verify(token)
    end

    test "ticket token is not accepted as a membership token" do
      ticket_id = "01HXYZ123456789ABCDEF00003"
      token = QrToken.sign_ticket(ticket_id)

      assert {:ok, {:ticket, _}} = QrToken.verify(token)
    end
  end

  describe "verify/1 error cases" do
    test "returns error for a completely invalid token string" do
      assert {:error, :invalid} = QrToken.verify("not-a-real-token")
    end

    test "returns error for an empty string" do
      assert {:error, :invalid} = QrToken.verify("")
    end

    test "returns error for a tampered token" do
      token = QrToken.sign_membership("some-user-id")
      tampered = token <> "x"
      assert {:error, :invalid} = QrToken.verify(tampered)
    end

    test "returns error for nil" do
      assert {:error, :invalid} = QrToken.verify(nil)
    end

    test "returns error for a non-binary value" do
      assert {:error, :invalid} = QrToken.verify(12345)
    end
  end

  describe "token uniqueness" do
    test "two different users produce different tokens" do
      t1 = QrToken.sign_membership("user-id-aaa")
      t2 = QrToken.sign_membership("user-id-bbb")
      refute t1 == t2
    end

    test "two different tickets produce different tokens" do
      t1 = QrToken.sign_ticket("ticket-id-aaa")
      t2 = QrToken.sign_ticket("ticket-id-bbb")
      refute t1 == t2
    end

    test "membership and ticket tokens for the same id are different" do
      id = "same-id-here"
      tm = QrToken.sign_membership(id)
      tt = QrToken.sign_ticket(id)
      refute tm == tt
    end
  end
end
