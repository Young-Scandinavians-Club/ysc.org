defmodule Ysc.LoggingTest do
  use ExUnit.Case, async: true

  describe "helpers (unit)" do
    test "normalize_opts/1 converts maps to keyword lists" do
      kw = Ysc.Logging.normalize_opts(%{a: 1, b: 2})
      assert Enum.sort(kw) == [a: 1, b: 2]
    end

    test "normalize_opts/1 passes through keyword lists" do
      assert Ysc.Logging.normalize_opts(foo: :bar) == [foo: :bar]
    end

    test "maybe_put_sentry_opt/3 skips nil values" do
      assert Ysc.Logging.maybe_put_sentry_opt([], :x, nil) == []
    end

    test "maybe_put_sentry_opt/3 puts non-nil values" do
      assert Ysc.Logging.maybe_put_sentry_opt([], :x, :y) == [x: :y]
    end

    test "maybe_merge_extra/2 returns base when extra is nil" do
      assert Ysc.Logging.maybe_merge_extra(%{a: 1}, nil) == %{a: 1}
    end

    test "maybe_merge_extra/2 merges maps" do
      assert Ysc.Logging.maybe_merge_extra(%{a: 1}, %{b: 2}) == %{a: 1, b: 2}
    end

    test "build_error_metadata/3 uses inspect for non-exception errors" do
      opts = [user_id: 1]
      result = Ysc.Logging.build_error_metadata(opts, :bad, nil)
      assert Keyword.get(result, :user_id) == 1
      assert Keyword.get(result, :error) == inspect(:bad)
    end

    test "build_error_metadata/3 uses Exception.message for exceptions" do
      err = ArgumentError.exception("nope")
      opts = [user_id: 1]
      result = Ysc.Logging.build_error_metadata(opts, err, nil)
      assert Keyword.get(result, :user_id) == 1
      assert Keyword.get(result, :error) == "nope"
    end

    test "build_error_metadata/3 adds stacktrace when present" do
      opts = []
      st = [{Test, :fun, 1, []}]
      result = Ysc.Logging.build_error_metadata(opts, :x, st)
      assert Keyword.has_key?(result, :stacktrace)
    end

    test "build_error_metadata/3 preserves pre-formatted stacktrace strings" do
      formatted = "    test/logging_test.exs:1: (test)\n"
      result = Ysc.Logging.build_error_metadata([], :x, formatted)
      assert Keyword.get(result, :stacktrace) == formatted
    end

    test "capture_sentry/6 accepts raw stacktrace lists without error" do
      err = RuntimeError.exception("boom")
      st = [{__MODULE__, :test, 1, []}]

      assert :ignored =
               Ysc.Logging.capture_sentry(err, st, nil, nil, "test message", [])
    end

    test "capture_sentry/6 ignores pre-formatted stacktrace strings" do
      err = RuntimeError.exception("boom")

      assert :ignored =
               Ysc.Logging.capture_sentry(
                 err,
                 "already formatted",
                 nil,
                 nil,
                 "test message",
                 []
               )
    end

    test "build_error_metadata/3 returns opts unchanged when error is nil" do
      opts = [booking_id: "b1"]
      assert Ysc.Logging.build_error_metadata(opts, nil, []) == opts
    end

    test "capture_sentry/6 returns :ok when error is nil" do
      assert :ok ==
               Ysc.Logging.capture_sentry(nil, [], nil, nil, "msg", [])
    end
  end
end
