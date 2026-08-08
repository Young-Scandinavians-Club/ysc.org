defmodule Mix.Tasks.Ci.EmailPreviews do
  @moduledoc """
  Renders email templates with notification preview samples to HTML files.

  Usage:

      mix ci.email_previews --output-dir tmp/email_previews \\
        --templates membership_ended,welcome_email

      mix ci.email_previews --output-dir tmp/email_previews --all
  """
  use Mix.Task

  @shortdoc "Render email templates to HTML for CI previews"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [output_dir: :string, templates: :string, all: :boolean]
      )

    output_dir =
      Keyword.get(opts, :output_dir) ||
        Mix.raise("--output-dir is required")

    Mix.Task.run("app.start")
    Code.ensure_loaded!(YscWeb.Dev.NotificationSamples)
    Code.ensure_loaded!(YscWeb.Emails.Notifier)

    names = template_names(opts)

    if names == [] do
      Mix.raise("No templates to render (pass --templates or --all)")
    end

    File.mkdir_p!(output_dir)

    results =
      Enum.map(names, fn name ->
        case YscWeb.Dev.NotificationSamples.render_email(name) do
          {:ok, html} ->
            path = Path.join(output_dir, "#{name}.html")
            File.write!(path, html)
            Mix.shell().info("rendered #{name} -> #{path}")
            {:ok, name, path}

          {:error, reason} ->
            Mix.shell().error("failed #{name}: #{inspect(reason)}")
            {:error, name, reason}
        end
      end)

    failures = for {:error, name, reason} <- results, do: {name, reason}

    if failures != [] do
      Mix.raise(
        "Failed to render #{length(failures)} template(s): #{inspect(failures)}"
      )
    end

    manifest =
      results
      |> Enum.map(fn {:ok, name, path} ->
        %{name: name, html: Path.basename(path)}
      end)
      |> Jason.encode!(pretty: true)

    File.write!(Path.join(output_dir, "manifest.json"), manifest <> "\n")
  end

  defp template_names(opts) do
    cond do
      Keyword.get(opts, :all, false) ->
        YscWeb.Emails.Notifier.template_names() ++ ["newsletter_edition"]

      templates = Keyword.get(opts, :templates) ->
        templates
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      true ->
        []
    end
    |> Enum.uniq()
    |> Enum.sort()
  end
end
