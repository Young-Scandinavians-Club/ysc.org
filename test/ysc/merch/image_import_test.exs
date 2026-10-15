defmodule Ysc.Merch.ImageImportTest do
  use Ysc.DataCase, async: true

  alias Ysc.Media.Image
  alias Ysc.Merch.ImageImport

  @png File.read!(Path.expand("../../support/fixtures/tiny.png", __DIR__))

  setup do
    %{admin: Ysc.AccountsFixtures.user_fixture(%{role: "admin"})}
  end

  defp serve(status, body, content_type \\ "image/png") do
    Req.Test.stub(ImageImport, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type(content_type)
      |> Plug.Conn.send_resp(status, body)
    end)
  end

  test "stores the original under merch/ and creates an image row", %{
    admin: admin
  } do
    serve(200, @png)

    assert {:ok, %Image{} = image} =
             ImageImport.import(
               "https://files.printful.test/a/tee.png",
               "Club Tee",
               admin
             )

    assert image.title == "Club Tee"
    assert image.alt_text == "Club Tee"
    assert image.user_id == admin.id
    assert %{"key" => "merch/" <> rest} = image.upload_data
    assert String.ends_with?(rest, "/image.png")
    assert image.raw_image_path =~ "merch/"
  end

  test "picks the extension from the content type when the URL has none", %{
    admin: admin
  } do
    serve(200, @png, "image/webp")

    assert {:ok, image} =
             ImageImport.import(
               "https://files.printful.test/a/render",
               "x",
               admin
             )

    assert String.ends_with?(image.upload_data["key"], "/image.webp")
  end

  test "rejects non-http URLs without fetching", %{admin: admin} do
    assert {:error, :blocked_url} =
             ImageImport.import("file:///etc/passwd", "x", admin)

    assert {:error, :blocked_url} =
             ImageImport.import("ftp://example.com/a.png", "x", admin)
  end

  test "non-200 responses are download failures", %{admin: admin} do
    serve(403, "denied")

    assert {:error, :download_failed} =
             ImageImport.import("https://files.printful.test/a.png", "x", admin)

    assert Repo.aggregate(Image, :count) == 0
  end

  test "empty bodies are rejected", %{admin: admin} do
    serve(200, "")

    assert {:error, :empty} =
             ImageImport.import("https://files.printful.test/a.png", "x", admin)
  end

  test "oversized bodies are rejected", %{admin: admin} do
    serve(200, :binary.copy("a", 16 * 1024 * 1024))

    assert {:error, :too_large} =
             ImageImport.import("https://files.printful.test/a.png", "x", admin)
  end

  test "redirects are not followed", %{admin: admin} do
    Req.Test.stub(ImageImport, fn conn ->
      conn
      |> Plug.Conn.put_resp_header(
        "location",
        "http://169.254.169.254/latest/meta-data"
      )
      |> Plug.Conn.send_resp(302, "")
    end)

    assert {:error, :download_failed} =
             ImageImport.import("https://files.printful.test/a.png", "x", admin)
  end

  test "a non-admin uploader is refused by media policy", %{} do
    serve(200, @png)
    member = Ysc.AccountsFixtures.user_fixture()

    assert {:error, _} =
             ImageImport.import(
               "https://files.printful.test/a.png",
               "x",
               member
             )

    assert Repo.aggregate(Image, :count) == 0
  end
end
