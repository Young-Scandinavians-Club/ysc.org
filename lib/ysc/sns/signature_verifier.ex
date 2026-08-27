defmodule Ysc.SNS.SignatureVerifier do
  @moduledoc """
  Verifies AWS SNS message signatures.

  Follows the AWS SNS signature verification spec:
  https://docs.aws.amazon.com/sns/latest/dg/sns-verify-signature-of-message.html

  Certificate and subscription-confirmation URLs are restricted to
  `sns.<region>.amazonaws.com` (and `.amazonaws.com.cn`). Allowing any
  `*.amazonaws.com` host is not sufficient: an attacker can host a
  self-signed cert on their own S3 bucket, forge a signed SNS envelope,
  and either fetch an arbitrary `SubscribeURL` or inject SES events
  (including hard-bounce suppressions).

  Topic ARNs are allowlisted separately (`:sns_allowed_topic_arns` /
  `SNS_TOPIC_ARN`). A valid AWS signature only proves the message came
  from SNS, not from *your* SES topic.
  """
  require Ysc.Logging

  # AWS SDK host check: sns.<region>.amazonaws.com with optional China TLD.
  @sns_host_regex ~r/^sns\.[a-z0-9-]{1,64}\.amazonaws\.com(\.cn)?$/i

  @doc """
  Verifies the signature of an SNS notification or subscription confirmation.

  Returns `:ok` if the signature is valid, `{:error, reason}` otherwise.
  """
  @spec verify(map()) :: :ok | {:error, atom()}
  def verify(message) when is_map(message) do
    with :ok <- validate_cert_url(message["SigningCertURL"]),
         {:ok, cert_pem} <- fetch_cert(message["SigningCertURL"]),
         {:ok, public_key} <- extract_public_key(cert_pem) do
      verify_signature(message, public_key)
    end
  end

  @doc """
  Returns `:ok` when `url` is an HTTPS SNS endpoint on a regional SNS host.

  ## Options

    * `:require_pem` — cert URLs must have a `.pem` path and no query/fragment
  """
  @spec validate_sns_https_url(String.t(), keyword()) :: :ok | {:error, atom()}
  def validate_sns_https_url(url, opts \\ [])

  def validate_sns_https_url(url, opts) when is_binary(url) do
    require_pem? = Keyword.get(opts, :require_pem, false)

    case URI.parse(url) do
      %URI{scheme: "https", host: host} = uri when is_binary(host) ->
        cond do
          uri.userinfo not in [nil, ""] ->
            {:error, :userinfo_not_allowed}

          uri.port not in [nil, 443] ->
            {:error, :invalid_cert_url}

          not sns_host?(host) ->
            {:error, :invalid_cert_host}

          path_unsafe?(uri.path) ->
            {:error, :invalid_cert_url}

          require_pem? and not pem_cert_path?(uri) ->
            {:error, :invalid_cert_url}

          true ->
            :ok
        end

      _ ->
        {:error, :invalid_cert_url}
    end
  end

  def validate_sns_https_url(_url, _opts), do: {:error, :invalid_cert_url}

  @doc """
  Resolves the signed SNS `Type` from the message body.

  The `x-amz-sns-message-type` header is not part of the signature. If it is
  present it must match the signed body `Type` so a captured Notification
  cannot be replayed as a SubscriptionConfirmation (which fetches SubscribeURL).
  """
  @spec signed_message_type(map(), String.t() | nil) ::
          {:ok, String.t() | nil} | {:error, atom()}
  def signed_message_type(message, header_type)
      when is_map(message) and (is_binary(header_type) or is_nil(header_type)) do
    body_type = message["Type"]

    cond do
      is_binary(header_type) and header_type != body_type ->
        {:error, :message_type_mismatch}

      true ->
        {:ok, body_type}
    end
  end

  @doc """
  Returns whether an SNS `TopicArn` may confirm a new HTTPS subscription.

  New subscriptions are fail-closed: `sns_allowed_topic_arns` must be
  configured and must include `topic_arn`. Otherwise anyone with an AWS
  account can subscribe `POST /webhooks/ses` and later publish forged SES
  bounce payloads that suppress mail for arbitrary addresses.
  """
  @spec allow_subscription_confirmation?(term()) :: boolean()
  def allow_subscription_confirmation?(topic_arn) when is_binary(topic_arn) do
    case allowed_topic_arns() do
      [] -> false
      allowed -> topic_arn in allowed
    end
  end

  def allow_subscription_confirmation?(_topic_arn), do: false

  @doc """
  Returns whether an SNS Notification `TopicArn` may be processed.

  When no allowlist is configured, notifications are accepted so an already
  confirmed SES topic keeps delivering. Once `SNS_TOPIC_ARN` is set, only
  those ARNs are accepted.
  """
  @spec allow_notification_topic?(term()) :: boolean()
  def allow_notification_topic?(topic_arn) when is_binary(topic_arn) do
    case allowed_topic_arns() do
      [] -> true
      allowed -> topic_arn in allowed
    end
  end

  def allow_notification_topic?(_topic_arn), do: false

  defp allowed_topic_arns do
    :ysc
    |> Application.get_env(:sns_allowed_topic_arns, [])
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
  end

  defp validate_cert_url(nil), do: {:error, :missing_cert_url}

  defp validate_cert_url(url) when is_binary(url) do
    case validate_sns_https_url(url, require_pem: true) do
      :ok ->
        :ok

      {:error, reason} = error ->
        Ysc.Logging.warning("SNS cert URL rejected", url: url, reason: reason)
        error
    end
  end

  defp sns_host?(host) do
    normalized =
      host
      |> String.downcase()
      |> String.trim_trailing(".")

    Regex.match?(@sns_host_regex, normalized)
  end

  defp path_unsafe?(nil), do: false

  defp path_unsafe?(path) when is_binary(path) do
    String.contains?(path, "..") or String.contains?(path, "\\")
  end

  defp pem_cert_path?(%URI{path: path, query: query, fragment: fragment}) do
    is_binary(path) and String.ends_with?(path, ".pem") and is_nil(query) and
      is_nil(fragment)
  end

  defp fetch_cert(url) do
    case Req.get(url,
           retry: false,
           receive_timeout: 10_000,
           max_redirects: 0
         ) do
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
