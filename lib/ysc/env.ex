defmodule Ysc.Env do
  @moduledoc """
  Helpers for runtime environment checks.

  Provides clean, consistent functions to check the current runtime environment
  without relying on Mix (which is not available in production releases).

  ## Examples

      if Ysc.Env.test?() do
        # Test-specific behavior
      end

      unless Ysc.Env.prod?() do
        # Development/test behavior
      end

      if Ysc.Env.sandbox?() do
        # Sandbox-specific behavior
      end

      if Ysc.Env.deployed?() do
        # Sandbox or production deployment behavior
      end
  """

  @doc """
  Returns the current environment as an atom.

  Falls back to :prod if not configured.
  Handles both atom and string values from configuration.

  ## Security Note
  Uses `String.to_atom/1` which is safe here because:
  - Input comes from application configuration (`:ysc, :environment`), not user input
  - Values are set at deployment/compile time by maintainers
  - Limited to known environment values: :dev, :test, :prod, :sandbox
  - This usage is explicitly ignored in `.sobelow-conf`
  """
  @spec current() :: atom()
  def current do
    case Application.get_env(:ysc, :environment, :prod) do
      env when is_atom(env) -> env
      # Safe: converts config string to atom (not user input)
      env when is_binary(env) -> String.to_atom(env)
    end
  end

  @doc """
  Returns true if running in test environment.
  """
  @spec test?() :: boolean()
  def test? do
    current() == :test
  end

  @doc """
  Returns true if running in development environment.
  """
  @spec dev?() :: boolean()
  def dev? do
    current() == :dev
  end

  @doc """
  Returns true if running in production environment.
  """
  @spec prod?() :: boolean()
  def prod? do
    current() in [:prod, :production]
  end

  @doc """
  Returns true if running in sandbox environment.
  """
  @spec sandbox?() :: boolean()
  def sandbox? do
    current() == :sandbox
  end

  @doc """
  Returns true if running in a deployed environment (sandbox or production).

  Used to gate behaviors that should only run on Fly deployments, such as
  downloading the MaxMind GeoIP database.
  """
  @spec deployed?() :: boolean()
  def deployed? do
    sandbox?() or prod?()
  end

  @doc """
  Returns true if running in a non-production environment (dev, test, or sandbox).

  Useful for enabling debug features or relaxing validation in lower environments.

  **Security note:** Sandbox is assumed to be internal-only (e.g. not publicly
  accessible). Features that bypass verification (e.g. dev/sandbox-only codes)
  rely on this assumption.
  """
  @spec non_prod?() :: boolean()
  def non_prod? do
    current() in [:dev, :test, :sandbox]
  end

  @doc """
  Returns the SES Configuration Set name for email tracking, or nil if not configured.

  When nil, no Configuration Set is attached to outgoing emails and SES event
  tracking (opens, clicks, bounces) is disabled.
  """
  @spec ses_configuration_set() :: String.t() | nil
  def ses_configuration_set do
    Application.get_env(:ysc, :ses_configuration_set)
  end
end
