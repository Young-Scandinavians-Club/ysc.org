defmodule Ysc.EnvTest do
  use ExUnit.Case, async: false

  setup do
    Ysc.Test.EnvHelper.reset_environment!()
    :ok
  end

  setup do
    Ysc.Test.EnvHelper.reset_environment!()
    :ok
  end

  describe "current/0" do
    test "returns the configured environment as an atom" do
      assert Ysc.Env.current() == :test
    end

    test "handles string environment configuration" do
      Ysc.Test.EnvHelper.with_environment("dev", fn ->
        assert Ysc.Env.current() == :dev
      end)
    end

    test "handles atom environment configuration" do
      Ysc.Test.EnvHelper.with_environment(:dev, fn ->
        assert Ysc.Env.current() == :dev
      end)
    end
  end

  describe "test?/0" do
    test "returns true in test environment" do
      assert Ysc.Env.test?() == true
    end
  end

  describe "dev?/0" do
    test "returns false in test environment" do
      assert Ysc.Env.dev?() == false
    end
  end

  describe "prod?/0" do
    test "returns false in test environment" do
      assert Ysc.Env.prod?() == false
    end

    test "returns true for production environment string" do
      Ysc.Test.EnvHelper.with_environment("production", fn ->
        assert Ysc.Env.prod?() == true
      end)
    end
  end

  describe "sandbox?/0" do
    test "returns false in test environment" do
      assert Ysc.Env.sandbox?() == false
    end

    test "returns true for sandbox environment string" do
      Ysc.Test.EnvHelper.with_environment("sandbox", fn ->
        assert Ysc.Env.sandbox?() == true
      end)
    end
  end

  describe "deployed?/0" do
    test "returns false in test environment" do
      assert Ysc.Env.deployed?() == false
    end

    test "returns false in dev environment" do
      Ysc.Test.EnvHelper.with_environment("dev", fn ->
        assert Ysc.Env.deployed?() == false
      end)
    end

    test "returns true in sandbox environment" do
      Ysc.Test.EnvHelper.with_environment("sandbox", fn ->
        assert Ysc.Env.deployed?() == true
      end)
    end

    test "returns true in production environment" do
      Ysc.Test.EnvHelper.with_environment("production", fn ->
        assert Ysc.Env.deployed?() == true
      end)
    end
  end

  describe "non_prod?/0" do
    test "returns true in test environment" do
      assert Ysc.Env.non_prod?() == true
    end
  end
end
