defmodule YscWeb.ReauthResumeTest do
  use ExUnit.Case, async: true

  alias YscWeb.ReauthResume

  test "sign/1 and verify/1 roundtrip" do
    intent = %{"purpose" => "email_change", "email" => "new@example.com"}
    token = ReauthResume.sign(intent)

    assert {:ok, ^intent} = ReauthResume.verify(token)
  end

  test "verify/1 rejects invalid tokens" do
    assert :error = ReauthResume.verify("not-a-valid-token")
    assert :error = ReauthResume.verify(nil)
  end

  test "append_to_path/2 adds reauth_resume query param" do
    path =
      ReauthResume.append_to_path("/users/settings", %{
        "purpose" => "email_change",
        "email" => "new@example.com"
      })

    uri = URI.parse(path)
    assert uri.path == "/users/settings"
    query = URI.decode_query(uri.query)
    assert is_binary(query["reauth_resume"])
    assert {:ok, _} = ReauthResume.verify(query["reauth_resume"])
  end

  test "append_to_path/2 preserves existing query params" do
    path =
      ReauthResume.append_to_path("/users/settings?tab=email", %{
        "purpose" => "phone_change",
        "phone" => "+14155550100"
      })

    query = path |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["tab"] == "email"
    assert is_binary(query["reauth_resume"])
  end
end
