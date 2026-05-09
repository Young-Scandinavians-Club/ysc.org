defmodule Mix.Tasks.Newsletter.UpdateDisposableDomains do
  @moduledoc """
  Downloads the latest disposable/temporary email domains list from GitHub.

  This task fetches the updated list from the disposable/disposable repository
  and saves it to priv/disposable_domains.txt. The list contains over 72,000
  known disposable email domains and is updated daily by the community.

  ## Usage

      mix newsletter.update_disposable_domains

  After updating the file, restart the application or call
  `Ysc.Newsletter.EmailValidator.reload_disposable_domains()` in a running
  system to reload the ETS table with the new domains.

  ## Automation

  This task can be scheduled to run periodically (e.g., weekly or monthly)
  via cron or in a CI/CD pipeline to keep the blocklist current.
  """
  use Mix.Task

  @shortdoc "Updates the disposable email domains list from GitHub"

  @github_url "https://raw.githubusercontent.com/disposable/disposable-email-domains/master/domains.txt"
  @output_filename "disposable_domains.txt"

  @impl Mix.Task
  def run(_args) do
    # Start required applications
    Mix.Task.run("app.start")

    Mix.shell().info("Downloading disposable email domains from GitHub...")
    Mix.shell().info("Source: #{@github_url}")

    case download_domains() do
      {:ok, content} ->
        save_domains(content)

      {:error, reason} ->
        Mix.shell().error("Failed to download domains: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp download_domains do
    case Req.get(@github_url, retry: :transient) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp save_domains(content) do
    output_file =
      Application.app_dir(:ysc, "priv") |> Path.join(@output_filename)

    File.write!(output_file, content)

    # Count domains for reporting
    domain_count =
      content
      |> String.split("\n", trim: true)
      |> Enum.reject(&(&1 == "" || String.starts_with?(&1, "#")))
      |> length()

    Mix.shell().info("✓ Downloaded #{domain_count} disposable domains")
    Mix.shell().info("✓ Saved to #{output_file}")

    # If running in a started application, reload the ETS table
    if Process.whereis(Ysc.Repo) do
      Mix.shell().info("Reloading ETS table...")

      case Ysc.Newsletter.EmailValidator.reload_disposable_domains() do
        {:ok, count} ->
          Mix.shell().info("✓ Reloaded #{count} domains into ETS table")

        {:error, reason} ->
          Mix.shell().error("Failed to reload ETS table: #{inspect(reason)}")
      end
    else
      Mix.shell().info(
        "Application not running. Restart the app to load the new domains."
      )
    end

    Mix.shell().info("")
    Mix.shell().info("Newsletter signup will now block these domains.")
  end
end
