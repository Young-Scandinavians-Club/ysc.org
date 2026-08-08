defmodule YscWeb.DevEmailPreviewController do
  @moduledoc false
  use YscWeb, :controller

  alias YscWeb.Dev.NotificationSamples
  alias YscWeb.Emails.Notifier

  def show(conn, %{"name" => name} = params) do
    name = normalize_name(name)

    case NotificationSamples.render_email(name) do
      {:ok, html} ->
        if params["mailbox"] == "1" do
          maybe_send_to_mailbox(name)
        end

        html(conn, html)

      {:error, :unknown} ->
        send_resp(conn, 404, "Unknown email template: #{name}")
    end
  end

  # Back-compat for the previous one-off path.
  def membership_ended(conn, params) do
    show(conn, Map.put(params, "name", "membership_ended"))
  end

  defp normalize_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.replace("-", "_")
  end

  defp maybe_send_to_mailbox(name) do
    with {:ok, assigns} <- NotificationSamples.email_assigns(name),
         {:ok, module} <- NotificationSamples.email_module(name),
         {:ok, subject} <- NotificationSamples.email_subject(name) do
      _ =
        Notifier.send_email_idempotent(
          "admin@ysc.org",
          "#{name}_dev_preview_#{System.system_time(:millisecond)}",
          subject,
          module,
          prepare_mailbox_assigns(name, assigns),
          "",
          nil
        )

      :ok
    else
      _ -> :ok
    end
  end

  defp prepare_mailbox_assigns("newsletter_edition", assigns) do
    case Map.get(assigns, :intro_text) do
      html when is_binary(html) ->
        Map.put(assigns, :intro_text, Phoenix.HTML.raw(html))

      _ ->
        assigns
    end
  end

  defp prepare_mailbox_assigns(_name, assigns), do: assigns
end
