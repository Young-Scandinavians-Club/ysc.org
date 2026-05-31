defmodule YscWeb.ErrorHTML do
  use YscWeb, :html

  import Plug.Conn, only: [put_status: 2]

  import Phoenix.Controller,
    only: [put_root_layout: 2, put_layout: 2, put_view: 2]

  # If you want to customize your error pages,
  # uncomment the embed_templates/1 call below
  # and add pages to the error directory:
  #
  #   * lib/ysc_web/controllers/error_html/404.html.heex
  #   * lib/ysc_web/controllers/error_html/500.html.heex
  #
  embed_templates "error_html/*"

  @doc """
  Renders a standalone HTML error page (no site header, nav, or footer).

  Controllers must use this instead of `put_view(ErrorHTML) |> render/2` so the
  response is not wrapped in the normal root/app layouts from the browser pipeline.
  """
  def render_page(conn, template)
      when template in [:"400", :"403", :"404", :"500"] do
    conn
    |> put_status(template_to_status(template))
    |> put_root_layout(html: false)
    |> put_layout(html: {YscWeb.Layouts, :error})
    |> put_view(html: __MODULE__)
    |> Phoenix.Controller.render(template)
  end

  defp template_to_status(:"400"), do: :bad_request
  defp template_to_status(:"403"), do: :forbidden
  defp template_to_status(:"404"), do: :not_found
  defp template_to_status(:"500"), do: :internal_server_error

  # The default is to render a plain text page based on
  # the template name. For example, "404.html" becomes
  # "Not Found".
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
