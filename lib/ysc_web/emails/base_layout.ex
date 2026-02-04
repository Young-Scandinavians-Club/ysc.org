defmodule YscWeb.Emails.BaseLayout do
  @moduledoc """
  Base email layout template.

  Defines the base MJML layout for all email templates.
  """
  use MjmlEEx.Layout, mjml_layout: "templates/base_layout.mjml.eex"
end
