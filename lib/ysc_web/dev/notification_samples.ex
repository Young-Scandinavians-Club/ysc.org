defmodule YscWeb.Dev.NotificationSamples do
  @moduledoc false
  # Sample data loader for /dev/notifications. Only used when `dev_routes: true`.

  alias Ysc.Accounts.{EmailCategories, SmsCategories}
  alias YscWeb.Emails
  alias YscWeb.Sms

  @samples_path "priv/dev/notification_preview_samples.exs"

  @doc """
  Loads the sample config from `priv/dev/notification_preview_samples.exs`.
  """
  def load do
    path = Path.join(File.cwd!(), @samples_path)

    {data, _binding} = Code.eval_file(path)
    data
  end

  def email_assigns(name) when is_binary(name) do
    case load().emails[name] do
      nil -> {:error, :unknown}
      assigns -> {:ok, assigns}
    end
  end

  def sms_variables(name) when is_binary(name) do
    case load().sms[name] do
      nil -> {:error, :unknown}
      variables -> {:ok, variables}
    end
  end

  def sms_auto_reply(name) when is_binary(name) do
    case load().sms_auto_replies[name] do
      nil -> {:error, :unknown}
      body -> {:ok, body}
    end
  end

  def render_email(name) when is_binary(name) do
    with {:ok, assigns} <- email_assigns(name),
         {:ok, module} <- email_module(name) do
      {:ok, module.render(prepare_render_assigns(name, assigns))}
    end
  end

  def render_sms(name) when is_binary(name) do
    with {:ok, variables} <- sms_variables(name),
         {:ok, module} <- sms_module(name) do
      {:ok, module.render(variables)}
    end
  end

  def email_subject(name) when is_binary(name) do
    case {email_module(name), email_assigns(name)} do
      {{:ok, module}, {:ok, assigns}} ->
        {:ok, resolve_subject(module, assigns)}

      {{:error, _} = err, _} ->
        err

      {_, {:error, _} = err} ->
        err
    end
  end

  def list_emails do
    notifier_names = Emails.Notifier.template_names()
    names = Enum.uniq(notifier_names ++ ["newsletter_edition"]) |> Enum.sort()

    Enum.map(names, fn name ->
      %{
        name: name,
        category: EmailCategories.get_category(name),
        subject: subject_or_name(name)
      }
    end)
  end

  def list_sms do
    templates =
      Enum.map(Sms.Notifier.template_names(), fn name ->
        %{
          name: name,
          kind: :template,
          category: SmsCategories.get_category(name),
          body: sms_body_or_empty(name)
        }
      end)

    auto_replies =
      Enum.map(["opt_in", "opt_out", "help"], fn name ->
        body =
          case sms_auto_reply(name) do
            {:ok, b} -> b
            _ -> ""
          end

        %{
          name: name,
          kind: :auto_reply,
          category: :auto_reply,
          body: body
        }
      end)

    templates ++ auto_replies
  end

  def email_module("newsletter_edition"), do: {:ok, Emails.NewsletterEdition}

  def email_module(name) when is_binary(name) do
    case Emails.Notifier.get_template_module(name) do
      nil -> {:error, :unknown}
      module -> {:ok, module}
    end
  end

  def sms_module(name) when is_binary(name) do
    case Sms.Notifier.get_template_module(name) do
      nil -> {:error, :unknown}
      module -> {:ok, module}
    end
  end

  def samples_path, do: @samples_path

  # Newsletter intro is stored as HTML in the sample config; mark it safe for MJML.
  defp prepare_render_assigns("newsletter_edition", assigns) do
    case Map.get(assigns, :intro_text) do
      html when is_binary(html) ->
        Map.put(assigns, :intro_text, Phoenix.HTML.raw(html))

      _ ->
        assigns
    end
  end

  defp prepare_render_assigns(_name, assigns), do: assigns

  defp subject_or_name(name) do
    case email_subject(name) do
      {:ok, subject} when is_binary(subject) and subject != "" -> subject
      _ -> name
    end
  end

  defp sms_body_or_empty(name) do
    case render_sms(name) do
      {:ok, body} -> body
      _ -> ""
    end
  end

  defp resolve_subject(module, assigns) do
    cond do
      function_exported?(module, :get_subject, 0) ->
        module.get_subject()

      function_exported?(module, :get_subject, 1) ->
        safe_get_subject_1(module, assigns)

      true ->
        humanize_template_name(module)
    end
  rescue
    _ -> humanize_template_name(module)
  end

  defp safe_get_subject_1(module, assigns) do
    module.get_subject(assigns)
  rescue
    _ ->
      try do
        module.get_subject(nil)
      rescue
        _ -> humanize_template_name(module)
      end
  end

  defp humanize_template_name(module) do
    if function_exported?(module, :get_template_name, 0) do
      module.get_template_name()
    else
      inspect(module)
    end
  end
end
