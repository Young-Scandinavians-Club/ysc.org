defmodule YscWeb.AccountSetupAccessTest do
  use Ysc.DataCase, async: true

  import Ysc.AccountsFixtures

  alias YscWeb.AccountSetupAccess

  describe "sign/1 and verify/2" do
    test "verify accepts a token signed for the same user id" do
      user = user_fixture()

      token = AccountSetupAccess.sign(user.id)

      assert AccountSetupAccess.verify(token, user.id)
    end

    test "verify rejects a token for a different user id" do
      user = user_fixture()
      other = user_fixture()

      token = AccountSetupAccess.sign(user.id)

      refute AccountSetupAccess.verify(token, other.id)
    end

    test "verify rejects blank or invalid tokens" do
      user = user_fixture()

      refute AccountSetupAccess.verify("", user.id)
      refute AccountSetupAccess.verify("not-a-token", user.id)
      refute AccountSetupAccess.verify(nil, user.id)
    end
  end

  describe "setup_path/2" do
    test "includes setup_token and preserves extra query params" do
      user = user_fixture()

      path =
        AccountSetupAccess.setup_path(user.id, %{
          from_signup: "true"
        })

      assert path =~ "/account/setup/#{user.id}"
      assert path =~ "setup_token="
      assert path =~ "from_signup=true"
    end
  end

  describe "email_verification_authorized?/3" do
    test "allows the account owner without a setup token" do
      user = user_fixture()

      assert AccountSetupAccess.email_verification_authorized?(
               user.id,
               user,
               false
             )
    end

    test "allows a visitor with setup_access_granted" do
      user = user_fixture()

      assert AccountSetupAccess.email_verification_authorized?(
               user.id,
               nil,
               true
             )
    end

    test "denies a stranger without setup access" do
      user = user_fixture()
      stranger = user_fixture()

      refute AccountSetupAccess.email_verification_authorized?(
               user.id,
               stranger,
               false
             )
    end
  end
end
