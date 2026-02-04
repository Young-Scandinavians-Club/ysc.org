defmodule YscWeb.TestLogFilter do
  @moduledoc """
  Custom logger filter for test environment to suppress expected error messages.

  During tests with async database operations, we sometimes see connection cleanup
  errors when test processes exit while async tasks are still running. These are
  expected and don't indicate actual problems, so we filter them out for cleaner
  test output.
  """

  require Logger

  @doc """
  Filters out expected database connection cleanup errors during tests.

  Returns :stop to prevent the log from being written, or the log_event unchanged
  to allow it through.
  """
  def filter_db_connection_errors(log_event, _state) do
    case log_event do
      %{
        level: :error,
        meta: %{
          mfa: {DBConnection.Connection, :handle_event, 4},
          file: "lib/db_connection/connection.ex"
        },
        msg: {:string, msg}
      } ->
        # Check if this is a disconnection error during test teardown
        msg_str = IO.iodata_to_binary(msg)

        if String.contains?(msg_str, "disconnected") and
             (String.contains?(msg_str, "owner") or
                String.contains?(msg_str, "client")) and
             String.contains?(msg_str, "exited") do
          # Suppress this expected error
          :stop
        else
          # Allow other db_connection errors through
          log_event
        end

      _ ->
        # Allow all other logs through
        log_event
    end
  end
end
