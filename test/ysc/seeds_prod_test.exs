defmodule Ysc.SeedsProdTest do
  use Ysc.DataCase, async: false

  import Ysc.AccountsFixtures

  alias Ysc.Accounts
  alias Ysc.Accounts.User
  alias Ysc.Repo

  @seeds Path.expand("../../priv/repo/seeds_prod.exs", __DIR__)

  setup do
    original = System.get_env("ADMIN_PASSWORD")

    on_exit(fn ->
      if original,
        do: System.put_env("ADMIN_PASSWORD", original),
        else: System.delete_env("ADMIN_PASSWORD")
    end)

    :ok
  end

  test "aborts the seed (and so the deploy) when ADMIN_PASSWORD is unset" do
    System.delete_env("ADMIN_PASSWORD")

    assert_raise RuntimeError, ~r/ADMIN_PASSWORD is not set/, fn ->
      Code.eval_file(@seeds)
    end
  end

  test "rejects the old public placeholder and short passwords" do
    for value <- ["change_me_in_production", "short", "   "] do
      System.put_env("ADMIN_PASSWORD", value)

      assert_raise RuntimeError, ~r/ADMIN_PASSWORD must be/, fn ->
        Code.eval_file(@seeds)
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

    defp capture_io(fun), do: ExUnit.CaptureIO.capture_io(fun)
  end
end
