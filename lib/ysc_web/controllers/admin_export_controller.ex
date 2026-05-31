defmodule YscWeb.AdminExportController do
  @moduledoc """
  Serves admin-generated CSV exports. Files are stored under `priv/static/exports`
  but are not listed in `Plug.Static` so exports are not world-readable by URL alone.
  """
  use YscWeb, :controller

  alias YscWeb.AdminExportFiles
  alias YscWeb.SafeSendFile

  require Ysc.Logging

  def show(conn, %{"filename" => filename}) do
    user = conn.assigns[:real_current_user] || conn.assigns[:current_user]

    cond do
      is_nil(user) or user.role not in [:admin, :volunteer] ->
        YscWeb.ErrorHTML.render_page(conn, :"403")

      not AdminExportFiles.valid_filename?(filename) ->
        YscWeb.ErrorHTML.render_page(conn, :"404")

      AdminExportFiles.export_owner_id(filename) != to_string(user.id) ->
        YscWeb.ErrorHTML.render_page(conn, :"403")

      true ->
        serve_export(conn, filename, user)
    end
  end

  defp serve_export(conn, filename, user) do
    case SafeSendFile.send_within(
           conn,
           200,
           AdminExportFiles.exports_root(),
           filename,
           prepare: fn conn, _absolute_path ->
             conn
             |> put_resp_header(
               "content-disposition",
               ~s(attachment; filename="#{filename}")
             )
             |> put_resp_content_type("text/csv")
           end
         ) do
      {:ok, conn} ->
        conn

      :error ->
        Ysc.Logging.warning(
          "Admin export download requested for missing file",
          user_id: user.id,
          filename: filename
        )

        YscWeb.ErrorHTML.render_page(conn, :"404")
    end
  end
end
