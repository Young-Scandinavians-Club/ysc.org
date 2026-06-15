defmodule Ysc.Tzdata.HttpTestPlug do
  @moduledoc false

  use Plug.Router

  plug :match
  plug :dispatch

  get "/tzdata" do
    conn
    |> put_resp_header("content-type", "application/octet-stream")
    |> put_resp_header("etag", "release-2024a")
    |> send_resp(200, "IANA tzdata bytes")
  end

  head "/tzdata" do
    conn
    |> put_resp_header("last-modified", "Mon, 01 Jan 2024 00:00:00 GMT")
    |> send_resp(304, "")
  end

  get "/redirect" do
    conn
    |> put_resp_header("location", "/tzdata")
    |> send_resp(302, "")
  end

  get "/echo-request-headers" do
    body =
      Enum.map_join(conn.req_headers, "\n", fn {k, v} -> "#{k}=#{v}" end)

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
