defmodule Mix.Tasks.LintNotificationSamples do
  @moduledoc """
  Ensures every assign used in email/SMS templates has a default in
  `priv/dev/notification_preview_samples.exs` for /dev/notifications rendering.
  """
  use Mix.Task

  @shortdoc "Lint notification preview sample assigns against templates"

  @samples_path "priv/dev/notification_preview_samples.exs"
  @email_templates_dir "lib/ysc_web/emails/templates"
  @sms_dir "lib/ysc_web/sms"

  @ignore_assigns MapSet.new(["inner_content"])

  # False positives from email addresses like info@ysc.org inside templates.
  @ignore_roots MapSet.new(["ysc", "gmail", "example", "hotmail", "yahoo"])

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")
    Code.ensure_loaded!(YscWeb.Emails.Notifier)
    Code.ensure_loaded!(YscWeb.Sms.Notifier)

    samples = load_samples()
    email_errors = lint_emails(samples)
    sms_errors = lint_sms(samples)

    errors = email_errors ++ sms_errors

    if errors == [] do
      Mix.shell().info("notification preview samples OK")
    else
      Enum.each(errors, fn error -> Mix.shell().error(error) end)
      Mix.shell().error("\n#{length(errors)} notification sample lint error(s)")
      System.halt(1)
    end
  end

  defp load_samples do
    path = Path.join(File.cwd!(), @samples_path)

    unless File.exists?(path) do
      Mix.raise("Missing sample config at #{@samples_path}")
    end

    {data, _} = Code.eval_file(path)
    data
  end

  defp lint_emails(samples) do
    names =
      YscWeb.Emails.Notifier.template_names()
      |> Kernel.++(["newsletter_edition"])
      |> Enum.uniq()
      |> Enum.sort()

    Enum.flat_map(names, fn name ->
      case samples.emails[name] do
        nil ->
          ["#{name}: missing sample config entry"]

        assigns when is_map(assigns) ->
          paths = extract_email_assign_paths(name)

          Enum.flat_map(paths, fn path ->
            if has_path?(assigns, path) do
              []
            else
              label = Enum.map_join(path, ".", &to_string/1)
              ["#{name}: missing sample for @#{label}"]
            end
          end)

        _ ->
          ["#{name}: sample config entry must be a map"]
      end
    end)
  end

  defp lint_sms(samples) do
    Enum.flat_map(YscWeb.Sms.Notifier.template_names(), fn name ->
      case samples.sms[name] do
        nil ->
          ["sms/#{name}: missing sample config entry"]

        variables when is_map(variables) ->
          keys = extract_sms_variable_keys(name)

          Enum.flat_map(keys, fn key ->
            if Map.has_key?(variables, key) or
                 Map.has_key?(variables, to_string(key)) do
              []
            else
              ["sms/#{name}: missing sample for :#{key}"]
            end
          end)

        _ ->
          ["sms/#{name}: sample config entry must be a map"]
      end
    end)
  end

  defp extract_email_assign_paths(name) do
    path =
      Path.join(File.cwd!(), @email_templates_dir)
      |> Path.join("#{name}.mjml.eex")

    if File.exists?(path) do
      path
      |> File.read!()
      |> extract_assign_paths_from_text()
    else
      []
    end
  end

  defp extract_assign_paths_from_text(text) do
    main_paths =
      Regex.scan(
        ~r/@([a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*)*)/,
        text
      )
      |> Enum.map(fn [_, path] -> path end)

    question_paths =
      Regex.scan(~r/@([a-zA-Z_][a-zA-Z0-9_]*\?)/, text)
      |> Enum.map(fn [_, path] -> path end)

    (main_paths ++ question_paths)
    |> Enum.reject(fn path ->
      root = path |> String.split(".", parts: 2) |> hd()

      MapSet.member?(@ignore_assigns, root) or
        MapSet.member?(@ignore_roots, root) or
        String.ends_with?(path, ".org") or
        String.ends_with?(path, ".com")
    end)
    |> Enum.uniq()
    |> Enum.map(&path_to_keys/1)
  end

  defp path_to_keys(path) do
    path
    |> String.split(".")
    |> Enum.map(&String.to_atom/1)
  end

  defp extract_sms_variable_keys(name) do
    module = YscWeb.Sms.Notifier.get_template_module(name)

    cond do
      is_nil(module) ->
        []

      function_exported?(module, :preview_keys, 0) ->
        module.preview_keys()

      true ->
        path =
          Path.join(File.cwd!(), @sms_dir)
          |> Path.join("#{name}.ex")

        if File.exists?(path) do
          extract_sms_keys_from_render(File.read!(path))
        else
          []
        end
    end
  end

  defp extract_sms_keys_from_render(source) do
    from_map_get =
      Regex.scan(
        ~r/Map\.get\(\s*variables\s*,\s*:([a-zA-Z_][a-zA-Z0-9_]*)/,
        source
      )
      |> Enum.map(fn [_, k] -> String.to_atom(k) end)

    from_dot =
      Regex.scan(~r/variables\.([a-zA-Z_][a-zA-Z0-9_]*)/, source)
      |> Enum.map(fn [_, k] -> String.to_atom(k) end)

    from_access =
      Regex.scan(~r/variables\[:([a-zA-Z_][a-zA-Z0-9_]*)\]/, source)
      |> Enum.map(fn [_, k] -> String.to_atom(k) end)

    from_pattern =
      case Regex.run(~r/def render\((%\{[^}]*\})/, source) do
        [_, map_lit] ->
          Regex.scan(~r/([a-zA-Z_][a-zA-Z0-9_]*):/, map_lit)
          |> Enum.map(fn [_, k] -> String.to_atom(k) end)

        nil ->
          []
      end

    (from_map_get ++ from_dot ++ from_access ++ from_pattern)
    |> Enum.uniq()
  end

  defp has_path?(_value, []), do: true

  defp has_path?(map, [key | rest]) when is_map(map) do
    cond do
      Map.has_key?(map, key) ->
        has_path?(Map.get(map, key), rest)

      Map.has_key?(map, to_string(key)) ->
        has_path?(Map.get(map, to_string(key)), rest)

      true ->
        false
    end
  end

  defp has_path?(_, _), do: false
end
