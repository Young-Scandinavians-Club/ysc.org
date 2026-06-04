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

  # Compile-time check for test environment
  @in_test Mix.env() == :test

  @doc false
  def normalize_opts(opts) do
    if is_map(opts), do: Enum.to_list(opts), else: opts
  end

  @doc false
  def maybe_put_sentry_opt(opts, _key, nil), do: opts
  def maybe_put_sentry_opt(opts, key, value), do: Keyword.put(opts, key, value)

  @doc false
  def maybe_merge_extra(base, nil), do: base

  def maybe_merge_extra(base, extra) when is_map(extra),
    do: Map.merge(base, extra)

  @doc false
  def build_error_metadata(opts, nil, _stacktrace), do: opts

  def build_error_metadata(opts, error, stacktrace) do
    error_message =
      if is_exception(error) do
        Exception.message(error)
      else
        inspect(error)
      end

    base = Keyword.put(opts, :error, error_message)

    if stacktrace do
      Keyword.put(base, :stacktrace, Exception.format_stacktrace(stacktrace))
    else
      base
    end
  end

  @doc false
  def capture_sentry(
        nil,
        _stacktrace,
        _sentry_extra,
        _sentry_tags,
        _message,
        _opts
      ),
      do: :ok

  def capture_sentry(
        error,
        stacktrace,
        sentry_extra,
        sentry_tags,
        message,
        opts
      ) do
    sentry_opts = []
    sentry_opts = maybe_put_sentry_opt(sentry_opts, :stacktrace, stacktrace)

    base_extra = %{log_message: message, metadata: Enum.into(opts, %{})}
    final_extra = maybe_merge_extra(base_extra, sentry_extra)
    sentry_opts = Keyword.put(sentry_opts, :extra, final_extra)
    sentry_opts = maybe_put_sentry_opt(sentry_opts, :tags, sentry_tags)

    if is_exception(error) do
      Sentry.capture_exception(error, sentry_opts)
    else
      Sentry.capture_message(
        "Error: #{message}",
        Keyword.merge(sentry_opts, level: :error)
      )
    end
  end

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
    if @in_test do
      quote do
        require Logger

        opts = Ysc.Logging.normalize_opts(unquote(opts))
        message = unquote(message)

        {error, opts} = Keyword.pop(opts, :error)
        {stacktrace, opts} = Keyword.pop(opts, :stacktrace)

        logger_metadata =
          Ysc.Logging.build_error_metadata(opts, error, stacktrace)

        Logger.error(message, logger_metadata)
        :ok
      end
    else
      quote do
        require Logger

        opts = Ysc.Logging.normalize_opts(unquote(opts))
        message = unquote(message)

        {error, opts} = Keyword.pop(opts, :error)
        {stacktrace, opts} = Keyword.pop(opts, :stacktrace)
        {sentry_extra, opts} = Keyword.pop(opts, :extra)
        {sentry_tags, opts} = Keyword.pop(opts, :tags)

        logger_metadata =
          Ysc.Logging.build_error_metadata(opts, error, stacktrace)

        Logger.error(message, logger_metadata)

        Ysc.Logging.capture_sentry(
          error,
          stacktrace,
          sentry_extra,
          sentry_tags,
          message,
          opts
        )

        :ok
      end
    end
  end

  @doc """
  Log an info message (no Sentry capture).
  """
  defmacro info(message, opts \\ []) do
    quote do
      require Logger
      Logger.info(unquote(message), Ysc.Logging.normalize_opts(unquote(opts)))
    end
  end

  @doc """
  Log a warning message (no Sentry capture).
  """
  defmacro warning(message, opts \\ []) do
    quote do
      require Logger

      Logger.warning(
        unquote(message),
        Ysc.Logging.normalize_opts(unquote(opts))
      )
    end
  end

  @doc """
  Sets the log level for an OTP application (passthrough to `Logger.put_application_level/2`).
  """
  def put_application_level(app, level) do
    Logger.put_application_level(app, level)
  end

  @doc """
  Log a debug message (no Sentry capture).
  """
  defmacro debug(message, opts \\ []) do
    quote do
      require Logger
      Logger.debug(unquote(message), Ysc.Logging.normalize_opts(unquote(opts)))
    end
  end
end
