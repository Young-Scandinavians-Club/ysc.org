defmodule Ysc.VerificationCacheTest do
  use ExUnit.Case, async: true

  alias Ysc.VerificationCache

  setup do
    # Ensure the GenServer is running (it may already be started by the app).
    case Process.whereis(VerificationCache) do
      nil -> start_supervised!({VerificationCache, []})
      _pid -> :ok
    end

    :ok
  end

  test "store_code/4 and get_code/2 returns stored code when not expired" do
    assert :ok =
             VerificationCache.store_code(
               "user-1",
               :email_verification,
               "123456",
               60
             )

    assert {:ok, "123456"} =
             VerificationCache.get_code("user-1", :email_verification)
  end

  test "get_code/2 returns :not_found when missing" do
    assert {:error, :not_found} =
             VerificationCache.get_code("missing", :sms_verification)
  end

  test "get_code/2 returns :expired when expired and removes entry" do
    assert :ok =
             VerificationCache.store_code(
               "user-2",
               :sms_verification,
               "999999",
               -1
             )

    assert {:error, :expired} =
             VerificationCache.get_code("user-2", :sms_verification)

    assert {:error, :not_found} =
             VerificationCache.get_code("user-2", :sms_verification)
  end

  test "verify_code/3 returns ok and removes when code matches" do
    assert :ok =
             VerificationCache.store_code(
               "user-3",
               :email_verification,
               "abc",
               60
             )

    assert {:ok, :verified} =
             VerificationCache.verify_code("user-3", :email_verification, "abc")

    assert {:error, :not_found} =
             VerificationCache.get_code("user-3", :email_verification)
  end

  test "verify_code/3 returns :invalid_code when code does not match" do
    assert :ok =
             VerificationCache.store_code(
               "user-4",
               :email_verification,
               "abc",
               60
             )

    assert {:error, :invalid_code} =
             VerificationCache.verify_code(
               "user-4",
               :email_verification,
               "nope"
             )

    assert {:ok, "abc"} =
             VerificationCache.get_code("user-4", :email_verification)
  end

  test "verify_code/3 returns :expired when expired" do
    assert :ok =
             VerificationCache.store_code(
               "user-5",
               :email_verification,
               "abc",
               -1
             )

    assert {:error, :expired} =
             VerificationCache.verify_code("user-5", :email_verification, "abc")

    assert {:error, :not_found} =
             VerificationCache.get_code("user-5", :email_verification)
  end

  test "remove_code/2 deletes code" do
    assert :ok =
             VerificationCache.store_code(
               "user-6",
               :email_verification,
               "abc",
               60
             )

    assert :ok = VerificationCache.remove_code("user-6", :email_verification)

    assert {:error, :not_found} =
             VerificationCache.get_code("user-6", :email_verification)
  end

  test "cleanup_expired/0 removes expired codes" do
    assert :ok =
             VerificationCache.store_code(
               "user-7",
               :email_verification,
               "abc",
               -1
             )

    assert :ok = VerificationCache.cleanup_expired()

    assert {:error, :not_found} =
             VerificationCache.get_code("user-7", :email_verification)
  end
end
