defmodule YscWeb.AnnualMeetingDocumentController do
  @moduledoc """
  Serves annual meeting and financial PDFs to authenticated members only.

  Files live under `priv/static/annual_meetings` but are not exposed via
  `Plug.Static` so they cannot be fetched without a session.
  """
  use YscWeb, :controller

  alias Ysc.MemberDocuments
  alias YscWeb.SafeSendFile

  def show(conn, %{"path" => path_segments}) when is_list(path_segments) do
    relative_path = Path.join(path_segments)
    filename = Path.basename(relative_path)

    with :ok <-
           MemberDocuments.validate_annual_meeting_relative_path(relative_path),
         {:ok, conn} <-
           SafeSendFile.send_within(
             conn,
             200,
             MemberDocuments.annual_meetings_root(),
             relative_path,
             prepare: fn conn, _absolute_path ->
               put_resp_header(
                 conn,
                 "content-disposition",
                 ~s(inline; filename="#{filename}")
               )
             end
           ) do
      conn
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> put_view(html: YscWeb.ErrorHTML)
        |> render(:"404")
    end
  end
end
