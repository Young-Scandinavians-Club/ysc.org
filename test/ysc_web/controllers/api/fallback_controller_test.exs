defmodule YscWeb.Api.FallbackControllerTest do
  use YscWeb.ConnCase, async: true

  alias YscWeb.Api.FallbackController

  describe "call/2" do
    test "missing_property returns 400 JSON", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :missing_property})
      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] =~ "property is required"
    end

    test "invalid_property returns 400 JSON", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :invalid_property})
      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] =~ "invalid property"
    end

    test "not_found returns 404 JSON", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :not_found})
      assert conn.status == 404
      assert Jason.decode!(conn.resp_body) == %{"error" => "not found"}
    end

    test "invalid_date returns 400 JSON with field name", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, {:invalid_date, "start"}})
      assert conn.status == 400
      body = Jason.decode!(conn.resp_body)
      assert body["error"] =~ "start"
      assert body["error"] =~ "ISO 8601"
    end

    test "changeset returns 422 with field errors", %{conn: conn} do
      changeset =
        {%{}, %{title: :string}}
        |> Ecto.Changeset.cast(%{"title" => ""}, [:title])
        |> Ecto.Changeset.validate_required(:title)

      conn = FallbackController.call(conn, {:error, changeset})
      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "validation failed"
      assert is_map(body["errors"])
    end

    test "binary reason returns 422 JSON", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, "bad input"})
      assert conn.status == 422
      assert Jason.decode!(conn.resp_body) == %{"error" => "bad input"}
    end

    test "non-binary error reason returns 500 JSON", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :unexpected_atom})
      assert conn.status == 500
      assert Jason.decode!(conn.resp_body)["error"] =~ "unexpected"
    end
  end
end
