defmodule YscWeb.AdminExportController do
  @moduledoc """
  Serves admin-generated CSV exports. Files are stored under `priv/static/exports`
  but are not listed in `Plug.Static` so exports are not world-readable by URL alone.
  """
  use YscWeb, :controller

  require Ysc.Logging

  @exports_root Path.join([:code.priv_dir(:ysc), "static", "exports"])

  @export_filename_regex ~r/^ysc-user-export-\d{4}-\d{2}-\d{2}-[0-9A-HJKMNP-TV-Z]{26}\.csv$/u

  def show(conn, %{"filename" => filename}) do
    user = conn.assigns[:real_current_user] || conn.assigns[:current_user]

    cond do
      is_nil(user) or user.role not in [:admin, :volunteer] ->
        conn
        |> put_status(:forbidden)
        |> put_view(html: YscWeb.ErrorHTML)
        |> render(:"403")

      not valid_export_filename?(filename) ->
        conn
        |> put_status(:not_found)
        |> put_view(html: YscWeb.ErrorHTML)
        |> render(:"404")

      true ->
        serve_export(conn, filename, user)
    end
  end

  defp valid_export_filename?(filename) when is_binary(filename) do
    Regex.match?(@export_filename_regex, filename)
  end

  defp valid_export_filename?(_), do: false

  defp serve_export(conn, filename, user) do
    absolute_path = Path.join(@exports_root, filename)

    if File.regular?(absolute_path) and path_within_exports_root?(absolute_path) do
      conn
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="#{filename}")
      )
      |> put_resp_content_type("text/csv")
      |> send_file(200, absolute_path)
    else
      Ysc.Logging.warning(
        "Admin export download requested for missing file",
        user_id: user.id,
        filename: filename
      )

      conn
      |> put_status(:not_found)
      |> put_view(html: YscWeb.ErrorHTML)
      |> render(:"404")
    end
  end

  defp path_within_exports_root?(absolute_path) do
    expanded = Path.expand(absolute_path)
    root = Path.expand(@exports_root)
    String.starts_with?(expanded, root <> "/")
  end
end
