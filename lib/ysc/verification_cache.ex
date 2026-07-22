defmodule Ysc.VerificationCache do
  @moduledoc """
  Stores short-lived verification codes (email/SMS) with expiration.

  Backed by Postgres so codes are available on every node in a multi-node
  deployment. Codes are encrypted at rest via `Ysc.Encrypted.Binary`.
  """

  import Ecto.Query

  alias Ysc.Repo
  alias Ysc.VerificationCode
  alias Ysc.Ci.QueryExplain.Fixtures

  @doc """
  Stores a verification code for a user with the given type and expiration time.

  Replaces any existing code for the same user and type.

  ## Parameters
  - user_id: The user ID (typically ULID string)
  - code_type: Atom like `:email_verification`, `:phone_verification`, etc.
  - code: The verification code string
  - expires_in_seconds: How long until the code expires (default: 600 = 10 minutes)
  """
  def store_code(user_id, code_type, code, expires_in_seconds \\ 600) do
    user_id = to_string(user_id)
    type = normalize_type(code_type)

    expires_at =
      DateTime.add(DateTime.utc_now(), expires_in_seconds, :second)
      |> DateTime.truncate(:second)

    %VerificationCode{user_id: user_id}
    |> VerificationCode.changeset(%{
      code_type: type,
      code: code,
      expires_at: expires_at
    })
    |> Repo.insert!(
      on_conflict: {:replace, [:code, :expires_at, :inserted_at]},
      conflict_target: [:user_id, :code_type]
    )

    :ok
  end

  @doc """
  Retrieves a verification code for a user if it exists and hasn't expired.

  Returns `{:ok, code}` if found and valid, `{:error, :not_found}` if not found,
  or `{:error, :expired}` if found but expired.
  """
  def get_code(user_id, code_type) do
    user_id = to_string(user_id)
    type = normalize_type(code_type)

    case Repo.get_by(VerificationCode, user_id: user_id, code_type: type) do
      nil ->
        {:error, :not_found}

      %VerificationCode{} = record ->
        if DateTime.compare(record.expires_at, DateTime.utc_now()) == :gt do
          {:ok, record.code}
        else
          delete_record(record)
          {:error, :expired}
        end
    end
  end

  @doc """
  Verifies a code for a user. If the code matches and is valid, removes it.

  Returns `{:ok, :verified}` if successful, `{:error, reason}` otherwise.
  """
  def verify_code(user_id, code_type, provided_code) do
    user_id = to_string(user_id)
    type = normalize_type(code_type)
    provided_code = to_string(provided_code)

    case Repo.get_by(VerificationCode, user_id: user_id, code_type: type) do
      nil ->
        {:error, :not_found}

      %VerificationCode{} = record ->
        cond do
          DateTime.compare(record.expires_at, DateTime.utc_now()) != :gt ->
            delete_record(record)
            {:error, :expired}

          codes_match?(provided_code, to_string(record.code)) ->
            case delete_record(record) do
              # Another node/process already consumed the code.
              0 -> {:error, :not_found}
              _ -> {:ok, :verified}
            end

          true ->
            {:error, :invalid_code}
        end
    end
  end

  @doc """
  Removes a code from storage (useful for cleanup after successful verification).
  """
  def remove_code(user_id, code_type) do
    user_id = to_string(user_id)
    type = normalize_type(code_type)

    from(c in VerificationCode,
      where: c.user_id == ^user_id and c.code_type == ^type
    )
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Deletes expired verification codes.

  Returns `{:ok, deleted_count}`.
  """
  def cleanup_expired do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      from(c in VerificationCode, where: c.expires_at <= ^now)
      |> Repo.delete_all()

    {:ok, count}
  end

  @doc false
  def ci_query_explain_query do
    user_id = Fixtures.ulid()
    type = "email_verification"

    from(c in VerificationCode,
      where: c.user_id == ^user_id and c.code_type == ^type
    )
  end

  defp normalize_type(type) when is_atom(type), do: Atom.to_string(type)
  defp normalize_type(type) when is_binary(type), do: type

  # secure_compare raises when lengths differ; treat that as a mismatch.
  defp codes_match?(provided, stored)
       when byte_size(provided) == byte_size(stored) do
    Plug.Crypto.secure_compare(provided, stored)
  end

  defp codes_match?(_, _), do: false

  # Prefer delete_all by primary key so concurrent verifiers do not raise
  # Ecto.StaleEntryError when another process already deleted the row.
  defp delete_record(%VerificationCode{id: id}) do
    {count, _} =
      from(c in VerificationCode, where: c.id == ^id)
      |> Repo.delete_all()

    count
  end
end
