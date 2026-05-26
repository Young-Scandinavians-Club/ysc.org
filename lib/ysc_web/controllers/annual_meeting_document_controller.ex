defmodule YscWeb.AnnualMeetingDocumentController do
  @moduledoc """
  Serves annual meeting and financial PDFs to authenticated members only.

  Files live under `priv/static/annual_meetings` but are not exposed via
  `Plug.Static` so they cannot be fetched without a session.
  """
  use YscWeb, :controller

  alias Ysc.MemberDocuments

  def show(conn, %{"path" => path_segments}) when is_list(path_segments) do
    relative_path = Path.join(path_segments)

    case MemberDocuments.annual_meeting_path(relative_path) do
      {:ok, absolute_path} ->
        filename = Path.basename(absolute_path)

        conn
        |> put_resp_header(
          "content-disposition",
          ~s(inline; filename="#{filename}")
        )
        |> send_file(200, absolute_path)

      :error ->
        conn
        |> put_status(:not_found)
        |> put_view(html: YscWeb.ErrorHTML)
        |> render(:"404")
    end
  end
end
