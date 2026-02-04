defmodule Ysc.TestLoggerBackend do
  @moduledoc """
  Custom logger backend for tests that filters out expected test errors.
  This reduces log noise from expected error scenarios during test runs.
  """

  @behaviour GenEvent

  # Patterns that indicate expected test errors (these are tested scenarios)
  @expected_error_patterns [
    "DBConnection.ConnectionError",
    "Postgrex.Protocol"
  ]

  def init(_) do
    {:ok, %{}}
  end

  def handle_event({level, _gl, {Logger, msg, _ts, md}}, state)
      when level == :error do
    # Suppress all db_connection errors - they're expected during test cleanup
    if md[:application] == :db_connection or
         md[:mfa] == {DBConnection.Connection, :handle_event, 4} do
      {:ok, state}
    else
      message_str = to_string(msg)
      # Also check metadata for error messages
      metadata_str = inspect(md)
      full_message = message_str <> " " <> metadata_str

      # Check if this is an expected test error - if so, completely suppress it
      is_expected_error =
        Enum.any?(@expected_error_patterns, fn pattern ->
          String.contains?(message_str, pattern) ||
            String.contains?(full_message, pattern)
        end) or String.contains?(message_str, "exited") or
          String.contains?(full_message, "exited")

      # Only log if it's not an expected test error
      unless is_expected_error do
        # Use minimal format for unexpected errors
        IO.puts(:stderr, "\n[ERROR] #{message_str}\n")
      end

      {:ok, state}
    end
  end

  def handle_event({_level, _gl, {Logger, _msg, _ts, _md}}, state) do
    # Don't log non-error messages (they should be filtered by level anyway)
    {:ok, state}
  end

  def handle_event(_, state) do
    {:ok, state}
  end

  def handle_call({:configure, _opts}, state) do
    {:ok, :ok, state}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end
end
