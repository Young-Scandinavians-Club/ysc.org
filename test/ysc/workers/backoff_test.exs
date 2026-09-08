defmodule Ysc.Workers.BackoffTest do
  use ExUnit.Case, async: true

  alias Ysc.Workers.Backoff

  describe "full_jitter/2" do
    test "stays within [1, exponential ceiling] with the defaults" do
      for attempt <- 1..6 do
        ceiling = min(trunc(60 * :math.pow(2, attempt)), 60 * 60)

        for _ <- 1..200 do
          wait = Backoff.full_jitter(attempt)
          assert wait >= 1
          assert wait <= ceiling
        end
      end
    end

    test "never returns less than the :min floor" do
      for attempt <- 1..8, _ <- 1..200 do
        assert Backoff.full_jitter(attempt, min: 30) >= 30
      end
    end

    test "never exceeds the :cap" do
      for attempt <- 1..12, _ <- 1..200 do
        assert Backoff.full_jitter(attempt, min: 30, cap: 600) <= 600
      end
    end

    test "the floor still holds once the cap is reached" do
      # attempt 12 is far past a 600s cap; result must be in [30, 600].
      for _ <- 1..500 do
        wait = Backoff.full_jitter(12, min: 30, cap: 600)
        assert wait in 30..600
      end
    end

    test "the ceiling grows with the attempt number" do
      max_for = fn attempt ->
        1..2_000
        |> Enum.map(fn _ ->
          Backoff.full_jitter(attempt, min: 5, cap: 10_000)
        end)
        |> Enum.max()
      end

      assert max_for.(1) < max_for.(3)
      assert max_for.(3) < max_for.(5)
    end
  end
end
