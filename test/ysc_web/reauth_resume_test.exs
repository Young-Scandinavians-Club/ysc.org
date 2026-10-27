defmodule YscWeb.ReauthResumeTest do
  use ExUnit.Case, async: true

  alias YscWeb.ReauthResume

  @user_id "01ARZ3NDEKTSV4RRFFQ69G5FAV"
  @other_user_id "01BX5ZZKBKACTAV9WEVGEMMVRZ"

  test "sign/1 and verify/2 roundtrip for the bound user" do
    intent = %{
      "user_id" => @user_id,
      "purpose" => "email_change",
      "email" => "new@example.com"
    }

    token = ReauthResume.sign(intent)

    assert {:ok, ^intent} = ReauthResume.verify(token, @user_id)
  end

  test "encrypts intent so sensitive fields are not readable from the token" do
    secret_email =
      "secret-resume-#{System.unique_integer([:positive])}@example.com"

    intent = %{
      "user_id" => @user_id,
      "purpose" => "email_change",
      "email" => secret_email
    }

    token = ReauthResume.sign(intent)

    refute String.contains?(token, secret_email)
    refute String.contains?(token, "email_change")
    refute String.contains?(token, @user_id)
    assert {:ok, ^intent} = ReauthResume.verify(token, @user_id)
  end

  test "verify/2 rejects a token bound to a different user" do
    token =
      ReauthResume.sign(%{
        "user_id" => @user_id,
        "purpose" => "email_change",
        "email" => "attacker@example.com"
      })

    assert :error = ReauthResume.verify(token, @other_user_id)
  end

  test "verify/2 rejects tokens without a user_id binding" do
    # Legacy / malformed payloads must fail closed.
    token =
      Phoenix.Token.encrypt(
        YscWeb.Endpoint,
        "reauth resume intent",
        %{"purpose" => "email_change", "email" => "x@example.com"},
        max_age: 600
      )

    assert :error = ReauthResume.verify(token, @user_id)
  end

  test "verify/2 rejects invalid tokens" do
    assert :error = ReauthResume.verify("not-a-valid-token", @user_id)
    assert :error = ReauthResume.verify(nil, @user_id)
    assert :error = ReauthResume.verify("not-a-valid-token", nil)
  end

  test "sign/1 requires user_id" do
    assert_raise ArgumentError, fn ->
      ReauthResume.sign(%{
        "purpose" => "email_change",
        "email" => "x@example.com"
      })
    end
  end

  test "append_to_path/2 adds reauth_resume query param" do
    path =
      ReauthResume.append_to_path("/users/settings", %{
        "user_id" => @user_id,
        "purpose" => "email_change",
        "email" => "new@example.com"
      })

    uri = URI.parse(path)
    assert uri.path == "/users/settings"
    query = URI.decode_query(uri.query)
    assert is_binary(query["reauth_resume"])
    assert {:ok, _} = ReauthResume.verify(query["reauth_resume"], @user_id)
  end

  test "append_to_path/2 preserves existing query params" do
    path =
      ReauthResume.append_to_path("/users/settings?tab=email", %{
        "user_id" => @user_id,
        "purpose" => "phone_change",
        "phone" => "+14155550100"
      })

    query = path |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["tab"] == "email"
    assert is_binary(query["reauth_resume"])
  end
end
