defmodule Ysc.Repo do
  use Ecto.Repo,
    otp_app: :ysc,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Inserts a changeset, retrying with a new reference_id when a unique constraint
  on reference_id fails (e.g. collision from ReferenceGenerator).

  The schema_module must implement `put_new_reference_id/1`.
  Options: `:max_attempts` (default 5).
  """
  def insert_with_reference_retry(changeset, schema_module, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 5)
    do_insert_with_reference_retry(changeset, schema_module, max_attempts)
  end

  defp do_insert_with_reference_retry(changeset, _schema_module, 0) do
    insert(changeset)
  end

  defp do_insert_with_reference_retry(changeset, schema_module, attempts) do
    case insert(changeset) do
      {:ok, record} ->
        {:ok, record}

      {:error, %Ecto.Changeset{} = cs} ->
        if reference_id_unique_constraint?(cs) do
          new_cs =
            cs
            |> clear_reference_id_error()
            |> schema_module.put_new_reference_id()

          do_insert_with_reference_retry(new_cs, schema_module, attempts - 1)
        else
          {:error, cs}
        end
    end
  end

  defp reference_id_unique_constraint?(changeset) do
    Enum.any?(changeset.errors, fn
      {:reference_id, {_, opts}} when is_list(opts) ->
        Keyword.get(opts, :constraint) == :unique

      _ ->
        false
    end)
  end

  defp clear_reference_id_error(changeset) do
    new_errors = Keyword.delete(changeset.errors, :reference_id)
    %{changeset | errors: new_errors, valid?: new_errors == []}
  end
end
