defmodule Ysc.SiteSettings.SocialUrlTest do
  use ExUnit.Case, async: true

  alias Ysc.SiteSettings.SocialUrl
  alias Ysc.SiteSettings.SiteSetting

  describe "validate/2" do
    test "accepts official HTTPS hosts for each social network" do
      assert :ok =
               SocialUrl.validate(
                 "facebook",
                 "https://www.facebook.com/YoungScandinaviansClub/"
               )

      assert :ok =
               SocialUrl.validate(
                 "instagram",
                 "https://www.instagram.com/theysc"
               )

      assert :ok =
               SocialUrl.validate(
                 "partiful",
                 "https://partiful.com/u/nm9TVCDwC3y28CL4fcTX"
               )

      assert :ok =
               SocialUrl.validate(
                 "whatsapp",
                 "https://chat.whatsapp.com/LvsXNcpGPuH2pSTuGGaUwF"
               )
    end

    test "allows clearing a social link with blank value" do
      assert :ok = SocialUrl.validate("facebook", "   ")
    end

    test "rejects javascript: and data: URLs (Finding 80)" do
      assert {:error, _} = SocialUrl.validate("facebook", "javascript:alert(1)")
      assert {:error, _} = SocialUrl.validate("instagram", "data:text/html,hi")
    end

    test "rejects http and lookalike hosts (Finding 80)" do
      assert {:error, _} =
               SocialUrl.validate("facebook", "http://www.facebook.com/ysc")

      assert {:error, _} =
               SocialUrl.validate(
                 "facebook",
                 "https://evil-facebook.com/ysc"
               )

      assert {:error, _} =
               SocialUrl.validate("partiful", "https://evilpartiful.com/u/x")

      assert {:error, _} =
               SocialUrl.validate(
                 "facebook",
                 "https://facebook.com:8443/ysc"
               )
    end

    test "rejects userinfo in URLs" do
      assert {:error, _} =
               SocialUrl.validate(
                 "facebook",
                 "https://user:pass@www.facebook.com/ysc"
               )
    end
  end

  describe "site_setting_changeset/2" do
    test "blocks persisting a javascript social URL" do
      setting = %SiteSetting{
        group: "socials",
        name: "facebook",
        value: "https://www.facebook.com/x"
      }

      changeset =
        SiteSetting.site_setting_changeset(setting, %{
          value: "javascript:alert(document.domain)"
        })

      refute changeset.valid?

      assert {"must be an HTTPS URL on an allowed host", _} =
               changeset.errors[:value]
    end

    test "accepts the seeded default Facebook URL" do
      setting = %SiteSetting{group: "socials", name: "facebook", value: ""}

      changeset =
        SiteSetting.site_setting_changeset(setting, %{
          value: "https://www.facebook.com/YoungScandinaviansClub/"
        })

      assert changeset.valid?
    end
  end
end
