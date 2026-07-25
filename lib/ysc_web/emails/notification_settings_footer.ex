defmodule YscWeb.Emails.NotificationSettingsFooter do
  @moduledoc """
  Reusable MJML footer block for notification emails with an unsubscribe or
  manage-settings link below the main email content.
  """
  use MjmlEEx.Component, mode: :runtime

  @impl MjmlEEx.Component
  def render(assigns) when is_list(assigns), do: render(Map.new(assigns))

  def render(assigns) when is_map(assigns) do
    url = Map.get(assigns, :url) || Map.get(assigns, "url")
    link_text = Map.get(assigns, :link_text) || Map.get(assigns, "link_text")
    context = Map.get(assigns, :context) || Map.get(assigns, "context")
    align = Map.get(assigns, :align) || Map.get(assigns, "align") || :center

    link =
      ~s(<a href="#{url}" style="color: #888888; text-decoration: underline;">#{link_text}</a>)

    inner =
      case context do
        nil -> link
        text -> "#{text} #{link}"
      end

    align_attr =
      case align do
        :left -> "left"
        "left" -> "left"
        _ -> "center"
      end

    """
    <mj-section padding="16px 48px 8px 48px">
      <mj-column padding="0">
        <mj-text align="#{align_attr}" font-size="12px" line-height="1.5" padding="0px" color="#888888">
          #{inner}
        </mj-text>
      </mj-column>
    </mj-section>
    """
  end
end
