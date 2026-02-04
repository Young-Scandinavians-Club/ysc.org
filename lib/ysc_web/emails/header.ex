defmodule YscWeb.Emails.HeaderBlock do
  @moduledoc """
  Email header component.

  Reusable header component for email templates with logo and branding.
  """
  use MjmlEEx.Component, mode: :runtime

  @impl MjmlEEx.Component
  def render(_assigns) do
    """
    <mj-section padding="32px">
      <mj-column padding="0">
        <mj-image padding="0px" src="#{logo_path()}" width="120px"></mj-image>
      </mj-column>
    </mj-section>
    """
  end

  def logo_path() do
    "#{YscWeb.Endpoint.url()}/images/ysc_logo.png"
  end
end
