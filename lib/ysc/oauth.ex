defmodule Ysc.OAuth do
  @moduledoc """
  Authorization-code OAuth provider for first-party apps (PKCE S256).

  Clients are registered in `:ysc, :oauth_clients` as a map keyed by
  `client_id`. Each client declares `client_secret`, `redirect_uris`, and
  which user `roles` / `states` may authorize.

  Query Console is the first client; add another map entry to onboard a new app.
  """
  import Ecto.Query

  alias Ysc.Accounts.User
  alias Ysc.Ci.QueryExplain.Fixtures
  alias Ysc.OAuth.AuthCode
  alias Ysc.Repo

  @hash_algorithm :sha256
  @code_bytes 32
  @code_ttl_seconds 60

  @type authorize_error ::
          :invalid_client
          | :invalid_redirect_uri
          | :unsupported_response_type
          | :missing_state
          | :invalid_pkce
          | :not_eligible

  @type token_error ::
          :invalid_client
          | :unsupported_grant_type
          | :invalid_grant
          | :invalid_request

  @doc "Registered OAuth clients (`client_id` => settings)."
  def clients do
    Application.get_env(:ysc, :oauth_clients, %{})
  end

  @doc "Looks up a single client by id."
  def client(client_id) when is_binary(client_id) do
    Map.get(clients(), client_id)
  end

  def client(_), do: nil

  @doc "Authorization code lifetime in seconds."
  def code_ttl_seconds, do: @code_ttl_seconds

  @doc """
  Validates a front-channel logout request for a registered client.

  Expects `client_id` and `post_logout_redirect_uri` (exact match against the
  client's `post_logout_redirect_uris` allowlist).
  """
  @spec validate_logout_request(map()) ::
          {:ok, String.t()} | {:error, :invalid_client | :invalid_redirect_uri}
  def validate_logout_request(params) when is_map(params) do
    with {:ok, _client_id, client} <- fetch_registered_client(params) do
      fetch_allowed_logout_redirect_uri(params, client)
    end
  end

  @doc """
  Validates authorize request params and creates a one-time auth code.

  Returns `{:ok, redirect_url}` with `code` and `state` query params, or
  `{:error, reason}`.
  """
  @spec create_authorization(User.t(), map()) ::
          {:ok, String.t()} | {:error, authorize_error()}
  def create_authorization(%User{} = user, params) when is_map(params) do
    with {:ok, client_id, client} <- fetch_registered_client(params),
         :ok <- ensure_eligible(user, client),
         {:ok, redirect_uri} <- fetch_allowed_redirect_uri(params, client),
         :ok <- validate_response_type(params),
         {:ok, state} <- fetch_state(params),
         {:ok, code_challenge} <- fetch_code_challenge(params) do
      {raw_code, auth_code} =
        build_auth_code(user, client_id, redirect_uri, code_challenge)

      {:ok, _} = Repo.insert(auth_code)

      {:ok, build_redirect_url(redirect_uri, raw_code, state)}
    end
  end

  @doc """
  Exchanges an authorization code for a user identity payload.

  Authenticates the client via `client_id`/`client_secret`, verifies PKCE,
  consumes the code (single-use), and returns user claims.
  """
  @spec exchange_token(map(), String.t() | nil, String.t() | nil) ::
          {:ok, map()} | {:error, token_error()}
  def exchange_token(params, basic_client_id, basic_client_secret)
      when is_map(params) do
    with {:ok, client_id, client_secret} <-
           resolve_client_credentials(
             params,
             basic_client_id,
             basic_client_secret
           ),
         :ok <- authenticate_client(client_id, client_secret),
         :ok <- validate_grant_type(params),
         {:ok, raw_code} <- fetch_required_string(params, "code"),
         {:ok, redirect_uri} <- fetch_required_string(params, "redirect_uri"),
         {:ok, code_verifier} <- fetch_required_string(params, "code_verifier"),
         :ok <- ensure_param_client_id(params, client_id) do
      consume_and_build_response(
        raw_code,
        redirect_uri,
        code_verifier,
        client_id
      )
    end
  end

  @doc false
  def ci_query_explain_query do
    from(c in AuthCode,
      where:
        c.hashed_code == ^:crypto.hash(@hash_algorithm, Fixtures.token()) and
          is_nil(c.consumed_at) and
          c.expires_at > ^Fixtures.now(),
      preload: [:user]
    )
  end

  defp fetch_registered_client(params) do
    case params["client_id"] do
      id when is_binary(id) ->
        case client(id) do
          %{client_secret: _, redirect_uris: _} = cfg -> {:ok, id, cfg}
          _ -> {:error, :invalid_client}
        end

      _ ->
        {:error, :invalid_client}
    end
  end

  defp ensure_eligible(%User{} = user, client) do
    roles = List.wrap(client[:roles] || client["roles"] || [:admin])
    states = List.wrap(client[:states] || client["states"] || [:active])

    if user.role in roles and user.state in states do
      :ok
    else
      {:error, :not_eligible}
    end
  end

  defp fetch_allowed_redirect_uri(params, client) do
    allowlist = List.wrap(client[:redirect_uris] || client["redirect_uris"])

    case params["redirect_uri"] do
      uri when is_binary(uri) ->
        if uri in allowlist do
          {:ok, uri}
        else
          {:error, :invalid_redirect_uri}
        end

      _ ->
        {:error, :invalid_redirect_uri}
    end
  end

  defp fetch_allowed_logout_redirect_uri(params, client) do
    allowlist =
      List.wrap(
        client[:post_logout_redirect_uris] ||
          client["post_logout_redirect_uris"]
      )

    case params["post_logout_redirect_uri"] do
      uri when is_binary(uri) and uri != "" ->
        if uri in allowlist do
          {:ok, uri}
        else
          {:error, :invalid_redirect_uri}
        end

      _ ->
        {:error, :invalid_redirect_uri}
    end
  end

  defp validate_response_type(%{"response_type" => "code"}), do: :ok
  defp validate_response_type(_), do: {:error, :unsupported_response_type}

  defp fetch_state(%{"state" => state}) when is_binary(state) and state != "",
    do: {:ok, state}

  defp fetch_state(_), do: {:error, :missing_state}

  defp fetch_code_challenge(%{
         "code_challenge" => challenge,
         "code_challenge_method" => "S256"
       })
       when is_binary(challenge) and challenge != "" do
    {:ok, challenge}
  end

  defp fetch_code_challenge(_), do: {:error, :invalid_pkce}

  defp build_auth_code(user, client_id, redirect_uri, code_challenge) do
    raw = :crypto.strong_rand_bytes(@code_bytes)
    hashed = :crypto.hash(@hash_algorithm, raw)
    encoded = Base.url_encode64(raw, padding: false)

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(@code_ttl_seconds, :second)
      |> DateTime.truncate(:second)

    auth_code = %AuthCode{
      hashed_code: hashed,
      user_id: user.id,
      client_id: client_id,
      redirect_uri: redirect_uri,
      code_challenge: code_challenge,
      expires_at: expires_at
    }

    {encoded, auth_code}
  end

  defp build_redirect_url(redirect_uri, code, state) do
    uri = URI.parse(redirect_uri)

    query =
      (uri.query || "")
      |> URI.decode_query()
      |> Map.put("code", code)
      |> Map.put("state", state)
      |> URI.encode_query()

    URI.to_string(%{uri | query: query})
  end

  defp resolve_client_credentials(params, basic_id, basic_secret) do
    body_id = params["client_id"]
    body_secret = params["client_secret"]

    cond do
      is_binary(basic_id) and is_binary(basic_secret) ->
        {:ok, basic_id, basic_secret}

      is_binary(body_id) and is_binary(body_secret) ->
        {:ok, body_id, body_secret}

      true ->
        {:error, :invalid_client}
    end
  end

  defp authenticate_client(client_id, client_secret) do
    case client(client_id) do
      %{client_secret: expected} ->
        if secure_string_eq?(client_secret, expected) do
          :ok
        else
          {:error, :invalid_client}
        end

      _ ->
        {:error, :invalid_client}
    end
  end

  defp validate_grant_type(%{"grant_type" => "authorization_code"}), do: :ok
  defp validate_grant_type(_), do: {:error, :unsupported_grant_type}

  defp fetch_required_string(params, key) do
    case params[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :invalid_request}
    end
  end

  defp ensure_param_client_id(params, authenticated_client_id) do
    case params["client_id"] do
      nil ->
        :ok

      id when id == authenticated_client_id ->
        :ok

      _ ->
        {:error, :invalid_client}
    end
  end

  defp consume_and_build_response(
         raw_code,
         redirect_uri,
         code_verifier,
         client_id
       ) do
    case Base.url_decode64(raw_code, padding: false) do
      {:ok, decoded} ->
        hashed = :crypto.hash(@hash_algorithm, decoded)
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        client = client(client_id)

        Repo.transaction(fn ->
          auth_code =
            from(c in AuthCode,
              where: c.hashed_code == ^hashed,
              lock: "FOR UPDATE"
            )
            |> Repo.one()

          cond do
            is_nil(auth_code) or is_nil(client) ->
              Repo.rollback(:invalid_grant)

            not is_nil(auth_code.consumed_at) ->
              Repo.rollback(:invalid_grant)

            DateTime.compare(auth_code.expires_at, now) != :gt ->
              Repo.rollback(:invalid_grant)

            auth_code.client_id != client_id ->
              Repo.rollback(:invalid_grant)

            auth_code.redirect_uri != redirect_uri ->
              Repo.rollback(:invalid_grant)

            not pkce_valid?(code_verifier, auth_code.code_challenge) ->
              Repo.rollback(:invalid_grant)

            true ->
              auth_code
              |> Ecto.Changeset.change(%{consumed_at: now})
              |> Repo.update!()

              user = Repo.get!(User, auth_code.user_id)

              case ensure_eligible(user, client) do
                :ok ->
                  user_payload(user)

                {:error, _} ->
                  Repo.rollback(:invalid_grant)
              end
          end
        end)
        |> case do
          {:ok, payload} -> {:ok, payload}
          {:error, :invalid_grant} -> {:error, :invalid_grant}
          {:error, _} -> {:error, :invalid_grant}
        end

      :error ->
        {:error, :invalid_grant}
    end
  end

  defp pkce_valid?(code_verifier, code_challenge)
       when is_binary(code_verifier) and is_binary(code_challenge) do
    computed =
      :crypto.hash(@hash_algorithm, code_verifier)
      |> Base.url_encode64(padding: false)

    secure_string_eq?(computed, code_challenge)
  end

  defp pkce_valid?(_, _), do: false

  defp user_payload(%User{} = user) do
    %{
      "token_type" => "bearer",
      "expires_in" => 0,
      "user" => %{
        "id" => user.id,
        "email" => user.email,
        "display_name" => display_name(user),
        "role" => to_string(user.role),
        "state" => to_string(user.state)
      }
    }
  end

  defp display_name(%User{first_name: first, last_name: last}) do
    [first, last]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" ")
    |> case do
      "" -> "Unknown"
      name -> name
    end
  end

  defp secure_string_eq?(left, right)
       when is_binary(left) and is_binary(right) and
              byte_size(left) == byte_size(right) do
    Plug.Crypto.secure_compare(left, right)
  end

  defp secure_string_eq?(_, _), do: false
end
