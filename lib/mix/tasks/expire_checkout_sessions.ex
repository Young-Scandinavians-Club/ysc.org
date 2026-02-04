defmodule Mix.Tasks.ExpireCheckoutSessions do
  @moduledoc """
  Mix task to expire all pending checkout sessions.

  This task is useful for:
  - Admin operations
  - Testing scenarios
  - Maintenance tasks
  - Emergency situations

  ## Usage:
      mix expire_checkout_sessions
      mix expire_checkout_sessions --user USER_ID
      mix expire_checkout_sessions --event EVENT_ID
      mix expire_checkout_sessions --stats

  ## Options:
      --user USER_ID    Expire sessions for a specific user
      --event EVENT_ID  Expire sessions for a specific event
      --stats           Show statistics about pending sessions
  """

  use Mix.Task

  @shortdoc "Expire pending checkout sessions"

  @impl Mix.Task
  def run(args) do
    # Start the application
    Mix.Task.run("app.start")

    case parse_args(args) do
      {:stats} ->
        show_statistics()

      {:user, user_id} ->
        expire_user_sessions(user_id)

      {:event, event_id} ->
        expire_event_sessions(event_id)

      {:all} ->
        expire_all_sessions()

      {:help} ->
        show_help()
    end
  end

  defp parse_args(args) do
    case args do
      ["--stats"] -> {:stats}
      ["--user", user_id] -> {:user, user_id}
      ["--event", event_id] -> {:event, event_id}
      [] -> {:all}
      ["--help"] -> {:help}
      _ -> {:help}
    end
  end

  defp show_statistics do
    IO.puts("📊 Pending Checkout Session Statistics")
    IO.puts("=" |> String.duplicate(50))

    stats = Ysc.Tickets.get_pending_checkout_statistics()

    IO.puts("Total Pending Sessions: #{stats.total_pending_sessions}")
    IO.puts("Total Pending Tickets: #{stats.total_pending_tickets}")
    IO.puts("Generated at: #{DateTime.to_string(stats.generated_at)}")
    IO.puts("")

    if stats.by_event != [] do
      IO.puts("📅 By Event:")

      Enum.each(stats.by_event, fn event_stat ->
        IO.puts("  • #{event_stat.event_title}")

        IO.puts(
          "    Sessions: #{event_stat.pending_sessions}, Tickets: #{event_stat.pending_tickets}"
        )
      end)

      IO.puts("")
    end

    if stats.by_user != [] do
      IO.puts("👤 By User:")

      Enum.each(stats.by_user, fn user_stat ->
        IO.puts("  • #{user_stat.user_email}")

        IO.puts(
          "    Sessions: #{user_stat.pending_sessions}, Tickets: #{user_stat.pending_tickets}"
        )
      end)
    end
  end

  defp expire_user_sessions(user_id) do
    IO.puts("🔄 Expiring checkout sessions for user: #{user_id}")

    case Ysc.Tickets.expire_user_pending_checkout_sessions(user_id) do
      {:ok, count} ->
        if count > 0 do
          IO.puts(
            "✅ Successfully expired #{count} checkout session(s) for user #{user_id}"
          )
        else
          IO.puts("ℹ️  No pending checkout sessions found for user #{user_id}")
        end

      {:error, reason} ->
        IO.puts("❌ Failed to expire checkout sessions: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp expire_event_sessions(event_id) do
    IO.puts("🔄 Expiring checkout sessions for event: #{event_id}")

    case Ysc.Tickets.expire_event_pending_checkout_sessions(event_id) do
      {:ok, count} ->
        if count > 0 do
          IO.puts(
            "✅ Successfully expired #{count} checkout session(s) for event #{event_id}"
          )
        else
          IO.puts("ℹ️  No pending checkout sessions found for event #{event_id}")
        end

      {:error, reason} ->
        IO.puts("❌ Failed to expire checkout sessions: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp expire_all_sessions do
    IO.puts("🔄 Expiring all pending checkout sessions...")

    case Ysc.Tickets.expire_all_pending_checkout_sessions() do
      {:ok, count} ->
        if count > 0 do
          IO.puts("✅ Successfully expired #{count} checkout session(s)")
        else
          IO.puts("ℹ️  No pending checkout sessions found")
        end

      {:error, reason} ->
        IO.puts("❌ Failed to expire checkout sessions: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp show_help do
    IO.puts(@moduledoc)
  end
end
