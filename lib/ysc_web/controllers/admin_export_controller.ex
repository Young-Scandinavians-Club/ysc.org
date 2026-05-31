defmodule YscWeb.AdminExportController do
  @moduledoc """
  Serves admin-generated CSV exports. Files are stored under `priv/static/exports`
  but are not listed in `Plug.Static` so exports are not world-readable by URL alone.
  """
  use YscWeb, :controller

  alias YscWeb.SafeSendFile

  require Ysc.Logging

  @exports_root Path.join([:code.priv_dir(:ysc), "static", "exports"])

  @export_filename_regex ~r/^ysc-user-export-(\d{4}-\d{2}-\d{2})-([0-9A-HJKMNP-TV-Z]{26})-([0-9A-HJKMNP-TV-Z]{26})\.csv$/u

  def show(conn, %{"filename" => filename}) do
    user = conn.assigns[:real_current_user] || conn.assigns[:current_user]

    cond do
      is_nil(user) or user.role not in [:admin, :volunteer] ->
        YscWeb.ErrorHTML.render_page(conn, :"403")

      not valid_export_filename?(filename) ->
        YscWeb.ErrorHTML.render_page(conn, :"404")

      export_owner_id(filename) != user.id ->
        YscWeb.ErrorHTML.render_page(conn, :"403")

      true ->
        serve_export(conn, filename, user)
    end
  end

  defp export_owner_id(filename) do
    case Regex.run(@export_filename_regex, filename) do
      [_full, _date, owner_id, _file_ulid] -> owner_id
      _ -> nil
    end
  end

  defp valid_export_filename?(filename) when is_binary(filename) do
    Regex.match?(@export_filename_regex, filename)
  end

  defp valid_export_filename?(_), do: false

  defp serve_export(conn, filename, user) do
    case SafeSendFile.send_within(conn, 200, @exports_root, filename,
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
