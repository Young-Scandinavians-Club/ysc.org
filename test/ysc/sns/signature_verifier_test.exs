defmodule Ysc.SNS.SignatureVerifierTest do
  use ExUnit.Case, async: true

  alias Ysc.SNS.SignatureVerifier

  describe "validate_sns_https_url/2" do
    test "accepts regional SNS hosts including China TLD" do
      assert :ok ==
               SignatureVerifier.validate_sns_https_url(
                 "https://sns.us-west-2.amazonaws.com/?Action=ConfirmSubscription"
               )

      assert :ok ==
               SignatureVerifier.validate_sns_https_url(
                 "https://sns.us-east-1.amazonaws.com/SimpleNotificationService-abc.pem",
                 require_pem: true
               )

      assert :ok ==
               SignatureVerifier.validate_sns_https_url(
                 "https://sns.cn-north-1.amazonaws.com.cn/?Action=ConfirmSubscription"
               )
    end

    test "rejects S3 and other amazonaws.com hosts (Finding 32)" do
      assert {:error, :invalid_cert_host} ==
               SignatureVerifier.validate_sns_https_url(
                 "https://attacker-bucket.s3.amazonaws.com/forged.pem",
                 require_pem: true
               )

      assert {:error, :invalid_cert_host} ==
               SignatureVerifier.validate_sns_https_url(
                 "https://s3.amazonaws.com/attacker-bucket/forged.pem",
                 require_pem: true
               )

      assert {:error, :invalid_cert_host} ==
               SignatureVerifier.validate_sns_https_url(
                 "https://ec2.amazonaws.com/cert.pem",
                 require_pem: true
               )

      assert {:error, :invalid_cert_host} ==
               SignatureVerifier.validate_sns_https_url(
                 "https://sns.amazonaws.com/cert.pem",
                 require_pem: true
               )
    end

    test "rejects non-HTTPS, userinfo, non-443 ports, and path tricks" do
      assert {:error, :invalid_cert_url} ==
               SignatureVerifier.validate_sns_https_url(
                 "http://sns.us-west-2.amazonaws.com/cert.pem",
                 require_pem: true
               )

      assert {:error, :userinfo_not_allowed} ==
               SignatureVerifier.validate_sns_https_url(
                 "https://evil@sns.us-west-2.amazonaws.com/cert.pem",
                 require_pem: true
               )

      assert {:error, :invalid_cert_url} ==
               SignatureVerifier.validate_sns_https_url(
                 "https://sns.us-west-2.amazonaws.com:8443/cert.pem",
                 require_pem: true
               )

      assert {:error, :invalid_cert_url} ==
               SignatureVerifier.validate_sns_https_url(
                 "https://sns.us-west-2.amazonaws.com/../cert.pem",
                 require_pem: true
               )

      assert {:error, :invalid_cert_url} ==
               SignatureVerifier.validate_sns_https_url(
                 "https://sns.us-west-2.amazonaws.com/cert.pem?x=1",
                 require_pem: true
               )
    end

    test "rejects suffix/prefix host bypasses" do
      assert {:error, :invalid_cert_host} ==
               SignatureVerifier.validate_sns_https_url(
                 "https://sns.us-west-2.amazonaws.com.evil.example/cert.pem",
                 require_pem: true
               )

      assert {:error, :invalid_cert_host} ==
               SignatureVerifier.validate_sns_https_url(
                 "https://notsns.us-west-2.amazonaws.com/cert.pem",
                 require_pem: true
               )
    end

    test "accepts a trailing-dot DNS root on a regional SNS host" do
      assert :ok ==
               SignatureVerifier.validate_sns_https_url(
                 "https://sns.us-west-2.amazonaws.com./SimpleNotificationService-abc.pem",
                 require_pem: true
               )
    end

    test "rejects cert URLs that are not .pem or carry a fragment" do
      assert {:error, :invalid_cert_url} ==
               SignatureVerifier.validate_sns_https_url(
                 "https://sns.us-west-2.amazonaws.com/SimpleNotificationService-abc",
                 require_pem: true
               )

      assert {:error, :invalid_cert_url} ==
               SignatureVerifier.validate_sns_https_url(
                 "https://sns.us-west-2.amazonaws.com/cert.pem#x",
                 require_pem: true
               )
    end

    test "rejects nil or non-string URLs" do
      assert {:error, :invalid_cert_url} ==
               SignatureVerifier.validate_sns_https_url(nil)

      assert {:error, :invalid_cert_url} ==
               SignatureVerifier.validate_sns_https_url(:not_a_url)
    end
  end

  describe "signed_message_type/2" do
    test "requires unsigned header to match signed body Type" do
      message = %{"Type" => "Notification"}

      assert {:ok, "Notification"} ==
               SignatureVerifier.signed_message_type(message, "Notification")

      assert {:ok, "Notification"} ==
               SignatureVerifier.signed_message_type(message, nil)

      assert {:error, :message_type_mismatch} ==
               SignatureVerifier.signed_message_type(
                 message,
                 "SubscriptionConfirmation"
               )
    end
  end
end
