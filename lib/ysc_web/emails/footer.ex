defmodule YscWeb.Emails.FooterBlock do
  @moduledoc """
  Email footer component.

  Reusable footer component for email templates with social links and settings.
  """
  use MjmlEEx.Component, mode: :runtime

  alias Ysc.Settings

  @impl MjmlEEx.Component
  def render(_assigns) do
    """
    <mj-section background-color="transparent" border-bottom="1px solid #e0e0e0" border-left="none" border-right="none" border-top="none" padding-bottom="32px" padding-left="48px" padding-right="48px" padding-top="32px" padding="12px">
      <mj-column background-color="transparent" padding="0" background-color="transparent">
        <mj-social font-size="15px" icon-padding="0px" icon-size="40px" mode="horizontal" padding="0px">
          <mj-social-element background-color="transparent" src="#{social_icon_facebook()}" href="#{facebook_url()}" name="facebook-noshare" title="YSC on Facebook"></mj-social-element>
          <mj-social-element background-color="transparent" src="#{social_icon_instagram()}" href="#{instagram_url()}" name="instagram-noshare" title="YSC on Instagram"></mj-social-element>
        </mj-social>
      </mj-column>
    </mj-section>
    <mj-section padding="48px">
      <mj-column padding="0">
        <mj-text align="center" font-size="16px" font-weight="400" color="#71717b">The Young Scandinavians Club</mj-text>
        <mj-text align="center" font-size="12px" color="#71717b">
          <a href="#{YscWeb.Endpoint.url()}" class="link-nostyle">YSC.org</a>
        </mj-text>
      </mj-column>
    </mj-section>
    """
  end

  def instagram_url() do
    Settings.get_setting("instagram")
  end

  def facebook_url() do
    Settings.get_setting("facebook")
  end

  def social_icon_instagram() do
    "#{YscWeb.Endpoint.url()}/images/social_icon_instagram.png"
  end

  def social_icon_facebook() do
    "#{YscWeb.Endpoint.url()}/images/social_icon_facebook.png"
  end
end
