defmodule Ysc.Accounts.UserToken do
  @moduledoc """
  User token schema and utilities.

  Defines the UserToken database schema for authentication tokens including
  remember me tokens and password reset tokens.
  """
  use Ecto.Schema
  import Ecto.Query
  alias Ysc.Accounts.UserToken

  @hash_algorithm :sha256
  @rand_size 32

  # It is very important to keep the reset password token expiry short,
  # since someone with access to the email may take over the account.
  @reset_password_validity_in_days 1
  @change_email_validity_in_days 7
  @session_validity_in_days 60

  def session_validity_in_days, do: @session_validity_in_days

  @primary_key {:id, Ecto.ULID, autogenerate: true}
  @foreign_key_type Ecto.ULID
  @timestamps_opts [type: :utc_datetime]
  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :user, Ysc.Accounts.User, foreign_key: :user_id, references: :id

    timestamps(updated_at: false)
  end

  @doc """
  Generates a token that will be stored in a signed place,
  such as session or cookie. As they are signed, those
  tokens do not need to be hashed.

  The reason why we store session tokens in the database, even
  though Phoenix already provides a session cookie, is because
  Phoenix' default session cookies are not persisted, they are
  simply signed and potentially encrypted. This means they are
  valid indefinitely, unless you change the signing/encryption
  salt.

  Therefore, storing them allows individual user
  sessions to be expired. The token system can also be extended
  to store additional data, such as the device used for logging in.
  You could then use this information to display all valid sessions
  and devices in the UI and allow users to explicitly expire any
  session they deem invalid.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %UserToken{token: token, context: "session", user_id: user.id}}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any.

  The token is valid if it matches the value in the database and it has
  not expired (after @session_validity_in_days).
  """
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: user

    {:ok, query}
  end

  @doc """
  Builds a token and its hash to be delivered to the user's email.

  The non-hashed token is sent to the user email while the
  hashed part is stored in the database. The original token cannot be reconstructed,
  which means anyone with read-only access to the database cannot directly use
  the token in the application to gain access. Furthermore, if the user changes
  their email in the system, the tokens sent to the previous email are no longer
  valid.

  Users can easily adapt the existing code to provide other types of delivery methods,
  for example, by phone numbers.
  """
  def build_email_token(user, context) do
    build_hashed_token(user, context, user.email)
  end

  defp build_hashed_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: hashed_token,
       context: context,
       sent_to: sent_to,
       user_id: user.id
     }}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any.

  The given token is valid if it matches its hashed counterpart in the
  database and the user email has not changed. This function also checks
  if the token is being used within a certain period, depending on the
  context. The default context supported by this function is
  "reset_password". For verifying requests to change the email,
  see `verify_change_email_token_query/2`.
  """
  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)
        days = days_for_context(context)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            join: user in assoc(token, :user),
            where:
              token.inserted_at > ago(^days, "day") and
                token.sent_to == user.email,
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  # Passkey login tokens expire after 2 minutes (stored as seconds for query)
  @passkey_login_validity_in_seconds 120
  # Auto-login magic links expire after 90 seconds (matches UserSessionController)
  @auto_login_validity_in_seconds 90

  @doc """
  Builds a one-time token for completing a passkey login.

  The raw (unhashed) token is returned for embedding in the redirect URL.
  Only the hash is stored in the database. The token must be consumed
  (deleted) on first use to prevent replay attacks.
  """
  def build_passkey_login_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: hashed_token,
       context: "passkey_login",
       user_id: user.id
     }}
  end

  @doc """
  Verifies a passkey login token and returns a query for the associated user.

  The token must have been issued within the last #{@passkey_login_validity_in_seconds}
  seconds. The caller is responsible for deleting the token after a successful lookup
  to ensure it can only be used once.
  """
  def verify_passkey_login_token_query(token) do
    verify_one_time_login_token_query(
      token,
      "passkey_login",
      @passkey_login_validity_in_seconds
    )
  end

  @doc """
  Builds a one-time token for completing an auto-login redirect after account setup.

  The raw (unhashed) token is returned for embedding in the redirect URL.
  Only the hash is stored in the database. The token must be consumed
  (deleted) on first use to prevent replay attacks.
  """
  def build_auto_login_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: hashed_token,
       context: "auto_login",
       user_id: user.id
     }}
  end

  @doc """
  Verifies an auto-login token and returns a query for the associated user.

  The token must have been issued within the last #{@auto_login_validity_in_seconds}
  seconds. The caller is responsible for deleting the token after a successful lookup
  to ensure it can only be used once.
  """
  def verify_auto_login_token_query(token) do
    verify_one_time_login_token_query(
      token,
      "auto_login",
      @auto_login_validity_in_seconds
    )
  end

  defp verify_one_time_login_token_query(token, context, validity_in_seconds) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from t in by_token_and_context_query(hashed_token, context),
            join: user in assoc(t, :user),
            where: t.inserted_at > ago(^validity_in_seconds, "second"),
            select: {user, t}

        {:ok, query}

      :error ->
        :error
    end
  end

  # Mobile app bearer tokens (admin/volunteer sign-in) are long-lived so the
  # app doesn't need to re-prompt for credentials at every event.
  @mobile_session_validity_in_days 90

  @doc """
  Builds a long-lived bearer token for the admin/volunteer mobile app.

  Hashed at rest like the email tokens (not stored raw like the web session
  token) since this value is sent as a bearer credential on every API request
  rather than living inside a signed/encrypted cookie.
  """
  def build_mobile_token(user) do
    build_hashed_token(user, "mobile_session", nil)
  end

  @doc """
  Verifies a mobile bearer token and returns its underlying lookup query.

  The query returns the user found by the token, if any. Valid for
  #{@mobile_session_validity_in_days} days from issuance.
  """
  def verify_mobile_token_query(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, "mobile_session"),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(@mobile_session_validity_in_days, "day"),
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc """
  Hashes a raw mobile token value the same way `build_mobile_token/1` does,
  so callers can look up/delete a token row without re-verifying it.
  """
  def hash_mobile_token(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} -> {:ok, :crypto.hash(@hash_algorithm, decoded_token)}
      :error -> :error
    end
  end

  defp days_for_context("reset_password"), do: @reset_password_validity_in_days

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any.

  This is used to validate requests to change the user
  email. It is different from `verify_email_token_query/2` precisely because
  `verify_email_token_query/2` validates the email has not changed, which is
  the starting point by this function.

  The given token is valid if it matches its hashed counterpart in the
  database and if it has not expired (after @change_email_validity_in_days).
  The context must always start with "change:".
  """
  def verify_change_email_token_query(token, "change:" <> _ = context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            where:
              token.inserted_at > ago(@change_email_validity_in_days, "day")

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc """
  Returns the token struct for the given token value and context.
  """
  def by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end

  @doc """
  Gets all tokens for the given user for the given contexts.
  """
  def by_user_and_contexts_query(user, :all) do
    from t in UserToken, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, [_ | _] = contexts) do
    from t in UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end

  @doc false
  def ci_query_explain_query do
    alias Ysc.Ci.QueryExplain.Fixtures

    by_token_and_context_query(Fixtures.token(), "session")
  end
end
