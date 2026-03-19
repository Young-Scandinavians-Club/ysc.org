defmodule Ysc.SNS.SignatureVerifier do
  @moduledoc """
  Verifies AWS SNS message signatures.

  Follows the AWS SNS signature verification spec:
  https://docs.aws.amazon.com/sns/latest/dg/sns-verify-signature-of-message.html

  The signing certificate URL is validated to be from an amazonaws.com domain
  before being fetched to prevent SSRF attacks.
  """
  require Ysc.Logging

  @valid_cert_domains ~w(amazonaws.com)

  @doc """
  Verifies the signature of an SNS notification or subscription confirmation.

  Returns `:ok` if the signature is valid, `{:error, reason}` otherwise.

  Note: In test/dev environments where SNS is not used, this always returns `:ok`
  if the `SNS_SKIP_SIGNATURE_VERIFICATION` env var is set (for local testing only).
  """
  @spec verify(map()) :: :ok | {:error, atom()}
  def verify(message) when is_map(message) do
    with :ok <- validate_cert_url(message["SigningCertURL"]),
         {:ok, cert_pem} <- fetch_cert(message["SigningCertURL"]),
         {:ok, public_key} <- extract_public_key(cert_pem) do
      verify_signature(message, public_key)
    end
  end

  defp validate_cert_url(nil), do: {:error, :missing_cert_url}

  defp validate_cert_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) ->
        if Enum.any?(
             @valid_cert_domains,
             &(host == &1 or String.ends_with?(host, "." <> &1))
           ) do
          :ok
        else
          Ysc.Logging.warning("SNS cert URL has invalid host",
            url: url,
            host: host
          )

          {:error, :invalid_cert_host}
        end

      _ ->
        Ysc.Logging.warning("SNS cert URL is not a valid HTTPS URL", url: url)
        {:error, :invalid_cert_url}
    end
  end

  defp fetch_cert(url) do
    case Req.get(url) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        Ysc.Logging.warning("SNS cert fetch returned non-200",
          url: url,
          status: status
        )

        {:error, :cert_fetch_failed}

      {:error, reason} ->
        Ysc.Logging.warning("SNS cert fetch failed",
          url: url,
          reason: inspect(reason)
        )

        {:error, :cert_fetch_failed}
    end
  end

  defp extract_public_key(pem) do
    try do
      [{:Certificate, der, _}] = :public_key.pem_decode(pem)

      # Decode with :otp so the SPKI's public key is already in Elixir/Erlang term
      # form (e.g. {:RSAPublicKey, modulus, exponent}) ready for :public_key.verify/4.
      # Do NOT attempt to re-encode the OTPSubjectPublicKeyInfo back to DER —
      # the ASN.1 encoder expects the plain SubjectPublicKeyInfo record type and
      # will crash with a badarg on the OTP variant.
      cert = :public_key.pkix_decode_cert(der, :otp)
      # {:OTPCertificate, tbs, _sig_alg, _sig}
      tbs = elem(cert, 1)
      # {:OTPTBSCertificate, ..., spki, ...} — spki is at index 7
      spki = elem(tbs, 7)
      # {:OTPSubjectPublicKeyInfo, _algorithm, subject_public_key}
      public_key = elem(spki, 2)
      {:ok, public_key}
    rescue
      error ->
        Ysc.Logging.warning("Failed to extract public key from SNS cert",
          error: inspect(error)
        )

        {:error, :cert_parse_failed}
    end
  end

  defp verify_signature(message, public_key) do
    message_type = message["Type"]

    string_to_sign = build_string_to_sign(message, message_type)

    case Base.decode64(message["Signature"] || "") do
      {:ok, signature} ->
        if :public_key.verify(string_to_sign, :sha, signature, public_key) do
          :ok
        else
          {:error, :invalid_signature}
        end

      :error ->
        {:error, :invalid_signature_encoding}
    end
  end

  # SNS uses different fields depending on message type when building the signing string
  defp build_string_to_sign(message, "Notification") do
    fields = [
      "Message",
      "MessageId",
      "Subject",
      "Timestamp",
      "TopicArn",
      "Type"
    ]

    build_canonical_string(message, fields)
  end

  defp build_string_to_sign(message, type)
       when type in ["SubscriptionConfirmation", "UnsubscribeConfirmation"] do
    fields = [
      "Message",
      "MessageId",
      "SubscribeURL",
      "Timestamp",
      "Token",
      "TopicArn",
      "Type"
    ]

    build_canonical_string(message, fields)
  end

  defp build_string_to_sign(_message, type) do
    Ysc.Logging.warning("Unknown SNS message type for signature", type: type)
    ""
  end

  defp build_canonical_string(message, fields) do
    fields
    |> Enum.filter(&Map.has_key?(message, &1))
    |> Enum.map_join("", fn field -> "#{field}\n#{message[field]}\n" end)
  end
end
