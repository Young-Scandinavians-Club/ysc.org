defmodule Ysc.VerificationCacheTest do
  use Ysc.DataCase, async: true

  alias Ysc.VerificationCache

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
               "abc123",
               60
             )

    assert {:ok, :verified} =
             VerificationCache.verify_code(
               "user-3",
               :email_verification,
               "abc123"
             )

    assert {:error, :not_found} =
             VerificationCache.get_code("user-3", :email_verification)
  end

  test "verify_code/3 returns :invalid_code when code does not match" do
    assert :ok =
             VerificationCache.store_code(
               "user-4",
               :email_verification,
               "abc123",
               60
             )

    assert {:error, :invalid_code} =
             VerificationCache.verify_code(
               "user-4",
               :email_verification,
               "nope12"
             )

    assert {:ok, "abc123"} =
             VerificationCache.get_code("user-4", :email_verification)
  end

  test "verify_code/3 returns :expired when expired" do
    assert :ok =
             VerificationCache.store_code(
               "user-5",
               :email_verification,
               "abc123",
               -1
             )

    assert {:error, :expired} =
             VerificationCache.verify_code(
               "user-5",
               :email_verification,
               "abc123"
             )

    assert {:error, :not_found} =
             VerificationCache.get_code("user-5", :email_verification)
  end

  test "remove_code/2 deletes code" do
    assert :ok =
             VerificationCache.store_code(
               "user-6",
               :email_verification,
               "abc123",
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
               "abc123",
               -1
             )

    assert {:ok, 1} = VerificationCache.cleanup_expired()

    assert {:error, :not_found} =
             VerificationCache.get_code("user-7", :email_verification)
  end

  test "storing again for same key replaces code" do
    assert :ok =
             VerificationCache.store_code(
               "user-8",
               :email_verification,
               "first1",
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

  test "cleanup_expired/0 keeps valid codes and drops expired" do
    assert :ok =
             VerificationCache.store_code(
               "user-mix-a",
               :email_verification,
               "keep01",
               600
             )

    assert :ok =
             VerificationCache.store_code(
               "user-mix-b",
               :email_verification,
               "gone01",
               -1
             )

    assert {:ok, 1} = VerificationCache.cleanup_expired()

    assert {:ok, "keep01"} =
             VerificationCache.get_code("user-mix-a", :email_verification)

    assert {:error, :not_found} =
             VerificationCache.get_code("user-mix-b", :email_verification)
  end

  test "codes are readable across process boundaries (shared DB)" do
    assert :ok =
             VerificationCache.store_code(
               "user-shared",
               :phone_verification,
               "555555",
               600
             )

    task =
      Task.async(fn ->
        VerificationCache.get_code("user-shared", :phone_verification)
      end)

    assert {:ok, "555555"} = Task.await(task)
  end

  test "verify_code/3 rejects different-length codes without raising" do
    assert :ok =
             VerificationCache.store_code(
               "user-len",
               :email_verification,
               "123456",
               60
             )

    assert {:error, :invalid_code} =
             VerificationCache.verify_code(
               "user-len",
               :email_verification,
               "12345"
             )

    assert {:error, :invalid_code} =
             VerificationCache.verify_code(
               "user-len",
               :email_verification,
               "1234567"
             )

    assert {:ok, "123456"} =
             VerificationCache.get_code("user-len", :email_verification)
  end

  test "atom and string code_type values normalize to the same storage key" do
    assert :ok =
             VerificationCache.store_code(
               "user-type",
               :email_verification,
               "111111",
               60
             )

    assert :ok =
             VerificationCache.store_code(
               "user-type",
               "email_verification",
               "222222",
               60
             )

    # Both forms resolve to the same row (last write wins).
    assert {:ok, "222222"} =
             VerificationCache.get_code("user-type", :email_verification)

    assert {:ok, "222222"} =
             VerificationCache.get_code("user-type", "email_verification")
  end

  test "concurrent verify of the same code succeeds once" do
    assert :ok =
             VerificationCache.store_code(
               "user-race",
               :phone_verification,
               "777777",
               60
             )

    results =
      1..8
      |> Task.async_stream(
        fn _ ->
          VerificationCache.verify_code(
            "user-race",
            :phone_verification,
            "777777"
          )
        end,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == {:ok, :verified})) == 1

    assert Enum.all?(results, fn
             {:ok, :verified} -> true
             {:error, :not_found} -> true
             {:error, :invalid_code} -> true
             _ -> false
           end)

    assert {:error, :not_found} =
             VerificationCache.get_code("user-race", :phone_verification)
  end
end
