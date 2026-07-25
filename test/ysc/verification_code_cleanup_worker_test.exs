defmodule Ysc.VerificationCodeCleanupWorkerTest do
  @moduledoc """
  Comprehensive coverage for expired verification-code cleanup:
  `VerificationCache.cleanup_expired/0` and `VerificationCodeCleanupWorker`.
  """
  use Ysc.DataCase, async: true

  import Ecto.Query

  alias Ysc.Repo
  alias Ysc.VerificationCache
  alias Ysc.VerificationCode
  alias Ysc.VerificationCodeCleanupWorker

  @oban_config Application.compile_env!(:ysc, Oban)

  defp count_codes do
    Repo.aggregate(VerificationCode, :count)
  end

  defp count_for(user_id, type) do
    from(c in VerificationCode,
      where: c.user_id == ^user_id and c.code_type == ^to_string(type)
    )
    |> Repo.aggregate(:count)
  end

  defp insert_expired(user_id, type, code \\ "111111") do
    assert :ok = VerificationCache.store_code(user_id, type, code, -1)
  end

  defp insert_valid(user_id, type, code) do
    assert :ok = VerificationCache.store_code(user_id, type, code, 600)
  end

  # ---------------------------------------------------------------------------
  # Worker configuration
  # ---------------------------------------------------------------------------

  describe "Oban worker configuration" do
    test "runs on the maintenance queue with retries" do
      opts = VerificationCodeCleanupWorker.__opts__()
      assert opts[:queue] == :maintenance
      assert opts[:max_attempts] == 3
    end

    test "is registered in the Oban cron plugin every 15 minutes" do
      # Use compile-time config so parallel tests that temporarily override
      # Application env (e.g. Oban testing mode) cannot clobber :plugins.
      plugins = Keyword.fetch!(@oban_config, :plugins)

      cron_plugin =
        Enum.find(plugins, fn
          {Oban.Plugins.Cron, _} -> true
          _ -> false
        end)

      assert {Oban.Plugins.Cron, cron_opts} = cron_plugin
      crontab = Keyword.fetch!(cron_opts, :crontab)

      assert {"*/15 * * * *", VerificationCodeCleanupWorker} in crontab
    end

    test "can be enqueued as an Oban job" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %Oban.Job{worker: worker, queue: queue}} =
                 VerificationCodeCleanupWorker.new(%{}) |> Oban.insert()

        assert worker == "Ysc.VerificationCodeCleanupWorker"
        assert queue == "maintenance"
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # VerificationCache.cleanup_expired/0
  # ---------------------------------------------------------------------------

  describe "VerificationCache.cleanup_expired/0" do
    test "returns {:ok, 0} when the table is empty" do
      assert count_codes() == 0
      assert {:ok, 0} = VerificationCache.cleanup_expired()
    end

    test "returns {:ok, 0} when only unexpired codes exist" do
      insert_valid("cleanup-a", :email_verification, "111111")
      insert_valid("cleanup-b", :phone_verification, "222222")

      assert {:ok, 0} = VerificationCache.cleanup_expired()
      assert count_codes() == 2
    end

    test "deletes all expired codes and returns the count" do
      insert_expired("gone-1", :email_verification, "111111")
      insert_expired("gone-2", :phone_verification, "222222")
      insert_expired("gone-3", :email_verification, "333333")

      assert {:ok, 3} = VerificationCache.cleanup_expired()
      assert count_codes() == 0
    end

    test "keeps unexpired codes while deleting expired ones" do
      insert_valid("keep-email", :email_verification, "111111")
      insert_valid("keep-phone", :phone_verification, "222222")
      insert_expired("gone-email", :email_verification, "333333")
      insert_expired("gone-phone", :phone_verification, "444444")

      assert {:ok, 2} = VerificationCache.cleanup_expired()
      assert count_codes() == 2

      assert {:ok, "111111"} =
               VerificationCache.get_code("keep-email", :email_verification)

      assert {:ok, "222222"} =
               VerificationCache.get_code("keep-phone", :phone_verification)

      assert {:error, :not_found} =
               VerificationCache.get_code("gone-email", :email_verification)

      assert {:error, :not_found} =
               VerificationCache.get_code("gone-phone", :phone_verification)
    end

    test "deletes codes whose expires_at is exactly now" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      %VerificationCode{user_id: "boundary-now"}
      |> VerificationCode.changeset(%{
        code_type: "email_verification",
        code: "555555",
        expires_at: now
      })
      |> Repo.insert!()

      assert count_for("boundary-now", :email_verification) == 1
      assert {:ok, 1} = VerificationCache.cleanup_expired()
      assert count_for("boundary-now", :email_verification) == 0
    end

    test "keeps codes that expire in the near future" do
      expires_at =
        DateTime.utc_now()
        |> DateTime.add(60, :second)
        |> DateTime.truncate(:second)

      %VerificationCode{user_id: "boundary-future"}
      |> VerificationCode.changeset(%{
        code_type: "phone_verification",
        code: "666666",
        expires_at: expires_at
      })
      |> Repo.insert!()

      assert {:ok, 0} = VerificationCache.cleanup_expired()

      assert {:ok, "666666"} =
               VerificationCache.get_code(
                 "boundary-future",
                 :phone_verification
               )
    end

    test "is idempotent when run repeatedly" do
      insert_expired("idempotent", :email_verification)

      assert {:ok, 1} = VerificationCache.cleanup_expired()
      assert {:ok, 0} = VerificationCache.cleanup_expired()
      assert {:ok, 0} = VerificationCache.cleanup_expired()
      assert count_codes() == 0
    end

    test "deletes many expired rows across users and channels in one sweep" do
      for i <- 1..25 do
        insert_expired("bulk-email-#{i}", :email_verification, "10000#{i}")
        insert_expired("bulk-phone-#{i}", :phone_verification, "20000#{i}")
      end

      insert_valid("bulk-keep", :email_verification, "999999")

      assert count_codes() == 51
      assert {:ok, 50} = VerificationCache.cleanup_expired()
      assert count_codes() == 1

      assert {:ok, "999999"} =
               VerificationCache.get_code("bulk-keep", :email_verification)
    end

    test "does not affect a replacement unexpired code for the same user/type" do
      insert_expired("replace-me", :email_verification, "111111")
      # store replaces the expired row with a fresh one
      insert_valid("replace-me", :email_verification, "999999")

      assert {:ok, 0} = VerificationCache.cleanup_expired()

      assert {:ok, "999999"} =
               VerificationCache.get_code("replace-me", :email_verification)
    end
  end

  # ---------------------------------------------------------------------------
  # Worker perform/1
  # ---------------------------------------------------------------------------

  describe "perform/1" do
    test "returns :ok when there is nothing to delete" do
      assert count_codes() == 0
      assert :ok = VerificationCodeCleanupWorker.perform(%Oban.Job{})
    end

    test "returns :ok when only valid codes exist" do
      insert_valid("worker-valid", :email_verification, "123456")
      assert :ok = VerificationCodeCleanupWorker.perform(%Oban.Job{})

      assert {:ok, "123456"} =
               VerificationCache.get_code("worker-valid", :email_verification)
    end

    test "deletes expired codes and keeps valid ones" do
      insert_valid("worker-keep", :email_verification, "111111")
      insert_expired("worker-gone", :phone_verification, "222222")

      assert :ok = VerificationCodeCleanupWorker.perform(%Oban.Job{})

      assert {:ok, "111111"} =
               VerificationCache.get_code("worker-keep", :email_verification)

      assert {:error, :not_found} =
               VerificationCache.get_code("worker-gone", :phone_verification)
    end

    test "cleans both email and phone channels" do
      insert_expired("ch-email", :email_verification, "111111")
      insert_expired("ch-phone", :phone_verification, "222222")
      insert_valid("ch-keep-email", :email_verification, "333333")
      insert_valid("ch-keep-phone", :phone_verification, "444444")

      assert :ok = VerificationCodeCleanupWorker.perform(%Oban.Job{})

      assert count_for("ch-email", :email_verification) == 0
      assert count_for("ch-phone", :phone_verification) == 0
      assert count_for("ch-keep-email", :email_verification) == 1
      assert count_for("ch-keep-phone", :phone_verification) == 1
    end

    test "removes expired rows so they are no longer readable via get_code/2" do
      insert_expired("lazy", :email_verification, "555555")

      # Before cleanup the row still exists in the DB even though get would
      # treat it as expired (and lazily delete it). Assert row presence first.
      assert count_for("lazy", :email_verification) == 1

      assert :ok = VerificationCodeCleanupWorker.perform(%Oban.Job{})
      assert count_for("lazy", :email_verification) == 0

      assert {:error, :not_found} =
               VerificationCache.get_code("lazy", :email_verification)
    end

    test "can be run repeatedly without error (idempotent)" do
      insert_expired("repeat", :phone_verification)

      assert :ok = VerificationCodeCleanupWorker.perform(%Oban.Job{})
      assert :ok = VerificationCodeCleanupWorker.perform(%Oban.Job{})
      assert :ok = VerificationCodeCleanupWorker.perform(%Oban.Job{})

      assert count_codes() == 0
    end

    test "handles a large batch of expired codes" do
      for i <- 1..40 do
        insert_expired("batch-#{i}", :email_verification)
      end

      assert count_codes() == 40
      assert :ok = VerificationCodeCleanupWorker.perform(%Oban.Job{})
      assert count_codes() == 0
    end

    test "ignores job args and always sweeps globally" do
      insert_expired("args-gone", :email_verification, "111111")
      insert_valid("args-keep", :email_verification, "222222")

      assert :ok =
               VerificationCodeCleanupWorker.perform(%Oban.Job{
                 args: %{"user_id" => "args-keep"}
               })

      assert count_for("args-gone", :email_verification) == 0
      assert count_for("args-keep", :email_verification) == 1
    end

    test "survives when rows were already lazily deleted by get_code/2" do
      insert_expired("already-gone", :email_verification, "111111")

      # Lazy path deletes on read
      assert {:error, :expired} =
               VerificationCache.get_code("already-gone", :email_verification)

      assert count_for("already-gone", :email_verification) == 0
      assert :ok = VerificationCodeCleanupWorker.perform(%Oban.Job{})
    end
  end
end
