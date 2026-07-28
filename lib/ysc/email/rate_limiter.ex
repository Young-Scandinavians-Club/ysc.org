defmodule Ysc.Email.RateLimiter do
  @moduledoc """
  A PostgreSQL-backed fixed-window limiter shared by every application node.
  """
  import Ecto.Query

  alias Ysc.Repo

  @table "email_rate_limits"

  def check(destinations \\ 1)
      when is_integer(destinations) and destinations > 0 do
    key = "ses:#{Application.get_env(:ysc, :ses_region, "default")}"
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    window_seconds = Application.get_env(:ysc, :ses_rate_window_seconds, 1)
    max_rate = Application.get_env(:ysc, :ses_max_send_rate, 10)

    Repo.transaction(fn ->
      # An advisory transaction lock makes this atomic across Fly machines
      # without holding a row lock before the first insert.
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [key])

      row =
        Repo.one(
          from(r in @table,
            where: field(r, :key) == ^key,
            select: %{
              window_started_at: field(r, :window_started_at),
              used: field(r, :used),
              cooldown_until: field(r, :cooldown_until)
            }
          )
        )

      cond do
        row && row.cooldown_until &&
            DateTime.compare(row.cooldown_until, now) == :gt ->
          {:limited, DateTime.diff(row.cooldown_until, now, :second)}

        row &&
          DateTime.diff(now, row.window_started_at, :second) < window_seconds &&
            row.used + destinations > max_rate ->
          {:limited,
           max(
             1,
             window_seconds - DateTime.diff(now, row.window_started_at, :second)
           )}

        row &&
            DateTime.diff(now, row.window_started_at, :second) < window_seconds ->
          Repo.update_all(from(r in @table, where: field(r, :key) == ^key),
            inc: [used: destinations],
            set: [updated_at: now]
          )

          :allowed

        row ->
          Repo.update_all(from(r in @table, where: field(r, :key) == ^key),
            set: [
              window_started_at: now,
              used: destinations,
              cooldown_until: nil,
              updated_at: now
            ]
          )

          :allowed

        true ->
          Repo.insert_all(@table, [
            %{
              key: key,
              window_started_at: now,
              used: destinations,
              updated_at: now
            }
          ])

          :allowed
      end
    end)
    |> case do
      {:ok, :allowed} -> :ok
      {:ok, {:limited, seconds}} -> {:error, :rate_limited, max(1, seconds)}
      {:error, reason} -> {:error, :unavailable, reason}
    end
  end

  def throttle!(seconds) when is_integer(seconds) and seconds > 0 do
    key = "ses:#{Application.get_env(:ysc, :ses_region, "default")}"
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    until = DateTime.add(now, seconds, :second)

    Repo.insert_all(
      @table,
      [
        %{
          key: key,
          window_started_at: now,
          used: 0,
          cooldown_until: until,
          updated_at: now
        }
      ],
      on_conflict: [set: [cooldown_until: until, updated_at: now]],
      conflict_target: :key
    )

    :ok
  end
end
