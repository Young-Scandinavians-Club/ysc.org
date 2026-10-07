defmodule Ysc.SiteSettings.SocialUrl do
  @moduledoc """
  Validates public social-link settings before they are stored.

  Footer / header templates render these values as raw `href`s for every
  visitor. Without host/scheme checks an admin (or compromised admin session)
  could persist `javascript:` URLs or lookalike phishing hosts — a sink that
  bypasses the Trix HTML scrubber used elsewhere (Finding 80).
  """

  @social_hosts %{
    "facebook" => ["facebook.com", "fb.com", "fb.me", "m.facebook.com"],
    "instagram" => ["instagram.com"],
    "partiful" => ["partiful.com"],
    "whatsapp" => [
      "whatsapp.com",
      "wa.me",
      "chat.whatsapp.com",
      "api.whatsapp.com"
    ]
  }

  @doc """
  Returns `true` when `name` is a social URL setting that must be validated.
  """
  @spec social_setting?(term()) :: boolean()
  def social_setting?(name) when is_binary(name),
    do: Map.has_key?(@social_hosts, name)

  def social_setting?(_), do: false

  @doc """
  Validates a social URL for the given setting name.

  Returns `:ok` or `{:error, message}`.
  """
  @spec validate(String.t(), term()) :: :ok | {:error, String.t()}
  def validate(name, value) when is_binary(name) and is_binary(value) do
    trimmed = String.trim(value)

    # Empty clears the footer link (templates treat blank as absent).
    if trimmed == "" do
      :ok
    else
      validate_parsed(name, trimmed)
    end
  end

  def validate(_name, _value), do: {:error, "must be a valid HTTPS URL"}

  defp validate_parsed(name, url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host, userinfo: userinfo} = uri
      when is_binary(host) and host != "" and userinfo in [nil, ""] ->
        if allowed_host?(name, host) and uri.port in [nil, 443] do
          :ok
        else
          {:error, "must be an official #{name} HTTPS URL"}
        end

      %URI{scheme: scheme}
      when scheme in ["http", "javascript", "data", "vbscript"] ->
        {:error, "must be an HTTPS URL on an allowed host"}

      _ ->
        {:error, "must be a valid HTTPS URL"}
    end
  end

  defp allowed_host?(name, host) do
    allowed = Map.fetch!(@social_hosts, name)

    normalized =
      host
      |> String.downcase()
      |> String.trim_trailing(".")

    Enum.any?(allowed, fn base ->
      normalized == base or String.ends_with?(normalized, "." <> base)
    end)
  end
end
