defmodule Ysc.Logging do
  @moduledoc """
  Custom logging module that automatically sends errors to Sentry.

  This module wraps Elixir's Logger and automatically captures exceptions
  and errors to Sentry when logging at the error level.

  ## Test Environment

  In test environment (compile-time check):
  - Logs are still emitted to Logger (so tests can capture them)
  - Sentry integration code is not compiled (no external calls during tests)

  ## Usage
      
      # Basic error logging (automatically sent to Sentry in prod)
      Ysc.Logging.error("Failed to process payment", user_id: user.id)
      
      # With exception and stacktrace
      rescue
        error ->
          Ysc.Logging.error("Payment processing failed",
            error: error,
            stacktrace: __STACKTRACE__,
            extra: %{payment_id: payment.id},
            tags: %{service: "stripe"}
          )
      end
      
      # Other log levels work normally (not sent to Sentry)
      Ysc.Logging.info("User logged in", user_id: user.id)
      Ysc.Logging.warning("Rate limit approaching", current: 90, max: 100)
  """

  require Logger

  # Compile-time check for test environment
  @in_test Mix.env() == :test

  @doc """
  Log an error message and automatically send to Sentry if error/exception is present.

  ## Options

  - `:error` - An exception struct to capture in Sentry
  - `:stacktrace` - Stacktrace to attach (usually `__STACKTRACE__`)
  - `:extra` - Additional context as a map for Sentry
  - `:tags` - Tags to categorize the error in Sentry
  - All other keyword options are passed to Logger.error as metadata

  ## Examples

      # Simple error log
      Ysc.Logging.error("Something went wrong", user_id: 123)
      
      # With exception
      rescue
        _error ->
          Ysc.Logging.error("Failed to save", 
            error: error,
            stacktrace: __STACKTRACE__,
            entity_id: entity.id
          )
      end
      
      # With Sentry extras and tags
      Ysc.Logging.error("API call failed",
        error: error,
        stacktrace: __STACKTRACE__,
        extra: %{endpoint: "/api/users", status: 500},
        tags: %{service: "external_api", environment: "production"}
      )
  """
  defmacro error(message, opts \\ []) do
    # Capture the compile-time test flag
    in_test = @in_test

    # Build the Sentry integration code conditionally at compile-time
    sentry_code =
      if in_test do
        # In test: no Sentry calls at all
        quote do
          :ok
        end
      else
        # In production: full Sentry integration
        quote do
          if error do
            sentry_opts = []

            sentry_opts =
              if stacktrace do
                Keyword.put(sentry_opts, :stacktrace, stacktrace)
              else
                sentry_opts
              end

            # Build extra context for Sentry
            base_extra = %{
              log_message: message,
              metadata: Enum.into(opts, %{})
            }

            final_extra =
              if sentry_extra do
                Map.merge(base_extra, sentry_extra)
              else
                base_extra
              end

            sentry_opts = Keyword.put(sentry_opts, :extra, final_extra)

            sentry_opts =
              if sentry_tags do
                Keyword.put(sentry_opts, :tags, sentry_tags)
              else
                sentry_opts
              end

            # Capture the exception in Sentry
            if is_exception(error) do
              Sentry.capture_exception(error, sentry_opts)
            else
              # For non-exception errors, capture as a message
              Sentry.capture_message(
                "Error: #{message}",
                Keyword.merge(sentry_opts, level: :error)
              )
            end
          end
        end
      end

    quote do
      require Logger

      opts = unquote(opts)
      message = unquote(message)

      # Extract Sentry-specific options
      {error, opts} = Keyword.pop(opts, :error)
      {stacktrace, opts} = Keyword.pop(opts, :stacktrace)
      {sentry_extra, opts} = Keyword.pop(opts, :extra)
      {sentry_tags, opts} = Keyword.pop(opts, :tags)

      # Build Logger metadata from remaining options
      logger_metadata =
        if error do
          error_message =
            if is_exception(error) do
              Exception.message(error)
            else
              inspect(error)
            end

          base_metadata = Keyword.put(opts, :error, error_message)

          if stacktrace do
            Keyword.put(
              base_metadata,
              :stacktrace,
              Exception.format_stacktrace(stacktrace)
            )
          else
            base_metadata
          end
        else
          opts
        end

      # Log to Logger (always, in all environments)
      Logger.error(message, logger_metadata)

      # Send to Sentry (compile-time conditional)
      unquote(sentry_code)

      :ok
    end
  end

  @doc """
  Log an info message (no Sentry capture).
  """
  defmacro info(message, opts \\ []) do
    quote do
      require Logger
      Logger.info(unquote(message), unquote(opts))
    end
  end

  @doc """
  Log a warning message (no Sentry capture).
  """
  defmacro warning(message, opts \\ []) do
    quote do
      require Logger
      Logger.warning(unquote(message), unquote(opts))
    end
  end

  @doc """
  Log a debug message (no Sentry capture).
  """
  defmacro debug(message, opts \\ []) do
    quote do
      require Logger
      Logger.debug(unquote(message), unquote(opts))
    end
  end
end
