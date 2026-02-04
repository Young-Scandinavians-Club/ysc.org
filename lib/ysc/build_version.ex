defmodule Ysc.BuildVersion do
  @moduledoc """
  Provides the build version embedded at compile time.

  The version is set during the build process via the BUILD_VERSION environment variable.
  If not set, it falls back to the application version from mix.exs.
  """

  # Get version at compile time from environment variable or fallback to mix.exs version
  @build_version System.get_env("BUILD_VERSION") ||
                   (case Application.spec(:ysc, :vsn) do
                      nil -> "0.1.0"
                      vsn -> to_string(vsn)
                    end)

  @doc """
  Returns the build version embedded at compile time.

  This version is set during the build process and does not require
  git or any external commands at runtime.
  """
  def version, do: @build_version
end
