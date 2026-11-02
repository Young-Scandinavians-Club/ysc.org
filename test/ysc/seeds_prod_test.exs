defmodule Ysc.SeedsProdTest do
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Accounts.User
  alias Ysc.Repo

  @seeds Path.expand("../../priv/repo/seeds_prod.exs", __DIR__)
  @env_keys ["ADMIN_PASSWORD", "ENVIRONMENT", "APP_ENV", "FLY_APP_NAME"]

  setup do
    originals = Map.new(@env_keys, &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(originals, fn {key, value} ->
        if value,
          do: System.put_env(key, value),
          else: System.delete_env(key)
      end)
    end)

    clear_seed_env()
    :ok
  end

  test "aborts the seed (and so the deploy) when ADMIN_PASSWORD is unset" do
    assert_raise RuntimeError, ~r/ADMIN_PASSWORD is not set/, fn ->
      capture_io(fn -> Code.eval_file(@seeds) end)
    end
  end

  test "rejects the old public placeholder and short passwords" do
    for value <- ["change_me_in_production", "short", "   "] do
      System.put_env("ADMIN_PASSWORD", value)

      assert_raise RuntimeError, ~r/ADMIN_PASSWORD must be/, fn ->
        capture_io(fn -> Code.eval_file(@seeds) end)
      end
    end
  end

  describe "with the database" do
    @new_password "a-brand-new-admin-password-1"

    test "rotates a leftover placeholder password and drops its sessions" do
      admin =
        user_fixture(%{
          email: "admin@ysc.org",
          password: "change_me_in_production",
          role: :admin,
          state: :active
        })

      Accounts.generate_user_session_token(admin)
      System.put_env("ADMIN_PASSWORD", @new_password)

      capture_io(fn -> Code.eval_file(@seeds) end)

      reloaded = Repo.get!(User, admin.id)
      assert User.valid_password?(reloaded, @new_password)
      refute User.valid_password?(reloaded, "change_me_in_production")
      assert reloaded.role == :admin

      assert Repo.aggregate(
               Ysc.Accounts.UserToken.by_user_and_contexts_query(admin, :all),
               :count
             ) == 0
    end

    test "leaves an admin whose password is not the placeholder untouched" do
      admin =
        user_fixture(%{
          email: "admin@ysc.org",
          password: "some-other-long-password-9",
          role: :admin,
          state: :active
        })

      System.put_env("ADMIN_PASSWORD", @new_password)

      capture_io(fn -> Code.eval_file(@seeds) end)

      reloaded = Repo.get!(User, admin.id)
      assert User.valid_password?(reloaded, "some-other-long-password-9")
      refute User.valid_password?(reloaded, @new_password)
    end

    test "continues when ADMIN_PASSWORD is unset if the admin password is not the placeholder" do
      admin =
        user_fixture(%{
          email: "admin@ysc.org",
          password: "some-other-long-password-9",
          role: :admin,
          state: :active
        })

      capture_io(fn -> Code.eval_file(@seeds) end)

      reloaded = Repo.get!(User, admin.id)
      assert User.valid_password?(reloaded, "some-other-long-password-9")
      assert reloaded.role == :admin
    end

    test "aborts production seed when the leftover placeholder is on the account and ADMIN_PASSWORD is unset" do
      user_fixture(%{
        email: "admin@ysc.org",
        password: "change_me_in_production",
        role: :admin,
        state: :active
      })

      assert_raise RuntimeError, ~r/ADMIN_PASSWORD is not set/, fn ->
        capture_io(fn -> Code.eval_file(@seeds) end)
      end
    end

    test "sandbox continues when ADMIN_PASSWORD is unset and the leftover placeholder is still on the account" do
      admin = placeholder_admin_fixture()
      System.put_env("ENVIRONMENT", "sandbox")

      stderr = seed_sandbox_placeholder_warning()

      reloaded = Repo.get!(User, admin.id)
      assert User.valid_password?(reloaded, "change_me_in_production")
      assert reloaded.role == :admin
      assert stderr =~ "old public placeholder password"
      assert stderr =~ "ysc-sandbox"
    end

    test "sandbox continues when ADMIN_PASSWORD is the leftover placeholder" do
      admin = placeholder_admin_fixture()
      System.put_env("ENVIRONMENT", "sandbox")
      System.put_env("ADMIN_PASSWORD", "change_me_in_production")

      stderr = seed_sandbox_placeholder_warning()

      reloaded = Repo.get!(User, admin.id)
      assert User.valid_password?(reloaded, "change_me_in_production")
      assert reloaded.role == :admin
      assert stderr =~ "old public placeholder password"
    end

    test "sandbox continues when ADMIN_PASSWORD is too short and the leftover placeholder is still on the account" do
      admin = placeholder_admin_fixture()
      System.put_env("ENVIRONMENT", "sandbox")
      System.put_env("ADMIN_PASSWORD", "short")

      stderr = seed_sandbox_placeholder_warning()

      reloaded = Repo.get!(User, admin.id)
      assert User.valid_password?(reloaded, "change_me_in_production")
      assert reloaded.role == :admin
      assert stderr =~ "old public placeholder password"
    end

    test "aborts production seed when the leftover placeholder is on the account and ADMIN_PASSWORD is unusable" do
      placeholder_admin_fixture()
      System.put_env("ADMIN_PASSWORD", "change_me_in_production")

      assert_raise RuntimeError, ~r/ADMIN_PASSWORD must be/, fn ->
        capture_io(fn -> Code.eval_file(@seeds) end)
      end
    end

    test "continues when ADMIN_PASSWORD is unusable if the admin password is not the placeholder" do
      admin =
        user_fixture(%{
          email: "admin@ysc.org",
          password: "some-other-long-password-9",
          role: :admin,
          state: :active
        })

      System.put_env("ADMIN_PASSWORD", "change_me_in_production")

      capture_io(fn -> Code.eval_file(@seeds) end)

      reloaded = Repo.get!(User, admin.id)
      assert User.valid_password?(reloaded, "some-other-long-password-9")
      refute User.valid_password?(reloaded, "change_me_in_production")
    end
  end

  defp capture_io(fun) when is_function(fun, 0),
    do: ExUnit.CaptureIO.capture_io(fun)

  defp capture_io(device, fun), do: ExUnit.CaptureIO.capture_io(device, fun)

  defp clear_seed_env do
    Enum.each(@env_keys, &System.delete_env/1)
  end

  defp placeholder_admin_fixture do
    user_fixture(%{
      email: "admin@ysc.org",
      password: "change_me_in_production",
      role: :admin,
      state: :active
    })
  end

  defp seed_sandbox_placeholder_warning do
    capture_io(:stderr, fn ->
      capture_io(fn -> Code.eval_file(@seeds) end)
    end)
  end
end
