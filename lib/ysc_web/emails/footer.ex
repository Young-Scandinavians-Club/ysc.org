defmodule YscWeb.Emails.FooterBlock do
  @moduledoc """
  Email footer component.

  Reusable footer component for email templates with social links and settings.
  """
  use MjmlEEx.Component, mode: :runtime

  import YscWeb.Emails.Helpers, only: [absolute_url: 1, origin: 0]

  alias Ysc.{Organization, Settings}

  @impl MjmlEEx.Component
  def render(_assigns) do
    social_section = social_footer_section()

    """
    #{social_section}
    <mj-section padding="16px 48px 0 48px">
      <mj-column padding="0">
        <mj-image src="#{viking_on_bike_url()}" alt="Viking on a bike" width="180px" padding="0" align="center"></mj-image>
      </mj-column>
    </mj-section>
    <mj-section padding="12px 48px 32px 48px">
      <mj-column padding="0">
        <mj-text align="center" font-size="16px" font-weight="400" color="#71717b">#{Organization.name()}</mj-text>
        <mj-text align="center" font-size="12px" color="#71717b" line-height="1.5">
          #{Organization.mailing_address_single_line()}<br />
          <a href="#{origin()}" class="link-nostyle">YSC.org</a>
        </mj-text>
      </mj-column>
    </mj-section>
    """
  end

  @doc """
  Absolute URL for the viking-on-bike illustration in the email footer.

  Email clients have poor SVG support, so this points at the transparent PNG export
  of `priv/static/images/viking_on_bike.svg`.
  """
  def viking_on_bike_url do
    absolute_url("/images/viking_on_bike.png")
  end

  def social_footer_section do
    elements =
      [
        {Settings.get_social_url("facebook"), social_icon_facebook(),
         "facebook-noshare", "YSC on Facebook"},
        {Settings.get_social_url("instagram"), social_icon_instagram(),
         "instagram-noshare", "YSC on Instagram"}
      ]
      |> Enum.map(fn
        {nil, _icon, _name, _title} ->
          nil

        {url, icon_src, name, title} when is_binary(url) ->
          ~s(<mj-social-element background-color="transparent" src="#{icon_src}" href="#{url}" name="#{name}" title="#{title}"></mj-social-element>)
      end)
      |> Enum.reject(&is_nil/1)

    case elements do
      [] ->
        ""

      els ->
        inner = Enum.join(els, "\n          ")

        """
        <mj-section background-color="transparent" border-bottom="1px solid #e0e0e0" border-left="none" border-right="none" border-top="none" padding-bottom="16px" padding-left="48px" padding-right="48px" padding-top="16px" padding="12px">
          <mj-column background-color="transparent" padding="0" background-color="transparent">
            <mj-social font-size="15px" icon-padding="0px" icon-size="40px" mode="horizontal" padding="0px">
              #{inner}
            </mj-social>
          </mj-column>
        </mj-section>
        """
    end
  end

  def social_icon_instagram() do
    absolute_url("/images/social_icon_instagram.png")
  end

  def social_icon_facebook() do
    absolute_url("/images/social_icon_facebook.png")
  end
end
