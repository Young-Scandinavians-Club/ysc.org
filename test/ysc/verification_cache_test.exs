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

  test "storing again for same key replaces code" do
    assert :ok =
             VerificationCache.store_code(
               "user-8",
               :email_verification,
               "first",
               600
             )

    assert :ok =
             VerificationCache.store_code(
               "user-8",
               :email_verification,
               "second",
               600
             )

    assert {:ok, "second"} =
             VerificationCache.get_code("user-8", :email_verification)
  end

  test "periodic cleanup message removes expired entries" do
    assert :ok =
             VerificationCache.store_code(
               "user-9",
               :email_verification,
               "gone",
               -1
             )

    pid = Process.whereis(VerificationCache)
    send(pid, :cleanup)

    _ = VerificationCache.get_code("user-9-flush", :email_verification)

    assert {:error, :not_found} =
             VerificationCache.get_code("user-9", :email_verification)
  end

  test "cleanup_expired/0 keeps valid codes and drops expired" do
    assert :ok =
             VerificationCache.store_code(
               "user-mix-a",
               :email_verification,
               "keep",
               600
             )

    assert :ok =
             VerificationCache.store_code(
               "user-mix-b",
               :email_verification,
               "gone",
               -1
             )

    assert :ok = VerificationCache.cleanup_expired()

    assert {:ok, "keep"} =
             VerificationCache.get_code("user-mix-a", :email_verification)

    assert {:error, :not_found} =
             VerificationCache.get_code("user-mix-b", :email_verification)
  end

  test "cleanup_individual message removes matching entry" do
    assert :ok =
             VerificationCache.store_code(
               "user-indiv",
               :sms_verification,
               "code",
               600
             )

    pid = Process.whereis(VerificationCache)
    send(pid, {:cleanup_individual, {"user-indiv", :sms_verification}})

    assert {:error, :not_found} =
             VerificationCache.get_code("user-indiv", :sms_verification)
  end

  test "periodic cleanup removes expired and keeps valid entries" do
    assert :ok =
             VerificationCache.store_code(
               "user-p-a",
               :email_verification,
               "keep2",
               600
             )

    assert :ok =
             VerificationCache.store_code(
               "user-p-b",
               :email_verification,
               "gone2",
               -1
             )

    pid = Process.whereis(VerificationCache)
    send(pid, :cleanup)

    assert {:ok, "keep2"} =
             VerificationCache.get_code("user-p-a", :email_verification)

    assert {:error, :not_found} =
             VerificationCache.get_code("user-p-b", :email_verification)
  end
end
