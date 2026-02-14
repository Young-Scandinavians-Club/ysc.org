defmodule Mix.Tasks.CopyVendorAssets do
  @moduledoc """
  Copies vendor assets that need to be loaded as standalone scripts to priv/static/assets.

  This is needed for vendor scripts that use IIFE/UMD patterns and need to run
  before the main bundle to expose global variables (like Sentry).
  """
  use Mix.Task

  @shortdoc "Copy vendor assets to static directory"

  def run(_args) do
    # Source and destination paths
    vendor_dir = Path.join([File.cwd!(), "assets", "vendor"])
    dest_dir = Path.join([File.cwd!(), "priv", "static", "assets"])

    # Ensure destination directory exists
    File.mkdir_p!(dest_dir)

    # Copy Sentry bundle
    sentry_source = Path.join(vendor_dir, "bundle.tracing.replay.min.js")
    sentry_dest = Path.join(dest_dir, "sentry.min.js")

    case File.cp(sentry_source, sentry_dest) do
      :ok ->
        Mix.shell().info("Copied Sentry bundle to #{sentry_dest}")

      {:error, reason} ->
        Mix.shell().error("Failed to copy Sentry bundle: #{inspect(reason)}")
    end
  end
end
