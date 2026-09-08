defmodule Ysc.Workers.Backoff do
  @moduledoc """
  Shared retry-backoff helpers for Oban workers.

  `full_jitter/2` implements the "full jitter" strategy (AWS Architecture Blog,
  *Exponential Backoff And Jitter*): each retry waits a uniformly random
  duration in `[min, ceiling]`, where `ceiling` grows exponentially with the
  attempt number up to a cap. Randomising the *whole* interval — rather than
  adding a little jitter around a fixed exponential point — is what stops a
  batch of jobs that all failed together (a throttled upload queue, a rate
  limited third-party API) from retrying in lockstep and re-triggering the
  same failure.
  """

  # `2^attempt` seconds of headroom per attempt, starting at ~1 minute.
  @default_base_seconds 60
  # Never wait more than an hour between attempts.
  @default_cap_seconds 60 * 60
  # Stop doubling the ceiling past this attempt (2^9+ is already well past the
  # cap for any sane base, this just keeps :math.pow out of huge-float range).
  @exponent_cap 9

  @doc """
  Seconds to wait before the next attempt.

  Options:

    * `:base` - first-attempt ceiling, in seconds (default `#{@default_base_seconds}`)
    * `:cap`  - maximum backoff, in seconds (default `#{@default_cap_seconds}`)
    * `:min`  - floor, in seconds, so a retry never stampedes back in almost
      immediately after a failure (default `0`)

  With the defaults this matches the plain full-jitter formula the mailer and
  newsletter workers have always used; pass `:min` / `:cap` to tighten it for a
  particular worker.
  """
  @spec full_jitter(pos_integer(), keyword()) :: pos_integer()
  def full_jitter(attempt, opts \\ [])
      when is_integer(attempt) and attempt > 0 do
    base = Keyword.get(opts, :base, @default_base_seconds)
    cap = Keyword.get(opts, :cap, @default_cap_seconds)
    floor = Keyword.get(opts, :min, 0)

    ceiling =
      (base * :math.pow(2, min(attempt, @exponent_cap)))
      |> trunc()
      |> min(cap)
      |> max(floor + 1)

    floor + :rand.uniform(ceiling - floor)
  end
end
