defmodule QueryConsole.Workbooks do
  @moduledoc """
  Owner-scoped workbook CRUD with autosave revision history.
  """

  import Ecto.Query

  alias QueryConsole.Accounts.User
  alias QueryConsole.Repo
  alias QueryConsole.Workbooks.{Workbook, WorkbookRevision}

  def list_workbooks(%User{} = user) do
    from(w in Workbook,
      where: w.user_id == ^user.id,
      order_by: [desc: w.updated_at]
    )
    |> Repo.all()
  end

  def get_workbook(%User{} = user, id) do
    case Repo.get(Workbook, id) do
      %Workbook{user_id: user_id} = workbook when user_id == user.id ->
        {:ok, workbook}

      %Workbook{} ->
        {:error, :forbidden}

      nil ->
        {:error, :not_found}
    end
  end

  def create_workbook(%User{} = user, attrs \\ %{}) do
    %Workbook{user_id: user.id}
    |> Workbook.changeset(Map.merge(%{"title" => "Untitled", "sql" => ""}, stringify(attrs)))
    |> Repo.insert()
  end

  def update_workbook(%User{} = user, workbook_or_id, attrs) do
    with {:ok, workbook} <- resolve_workbook(user, workbook_or_id) do
      workbook
      |> Workbook.changeset(stringify(attrs))
      |> Repo.update()
    end
  end

  def delete_workbook(%User{} = user, workbook_or_id) do
    with {:ok, workbook} <- resolve_workbook(user, workbook_or_id) do
      Repo.delete(workbook)
    end
  end

  @doc """
  Autosaves SQL for an owned workbook and keeps the last N revisions.
  """
  def autosave(%User{} = user, workbook_or_id, sql) when is_binary(sql) do
    limit = Application.get_env(:query_console, :workbook_revision_limit, 50)

    Repo.transaction(fn ->
      with {:ok, workbook} <- resolve_workbook(user, workbook_or_id),
           {:ok, workbook} <-
             workbook
             |> Workbook.changeset(%{sql: sql})
             |> Repo.update(),
           {:ok, _rev} <- insert_revision(workbook, sql),
           :ok <- prune_revisions(workbook.id, limit) do
        workbook
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def list_revisions(%User{} = user, workbook_or_id) do
    with {:ok, workbook} <- resolve_workbook(user, workbook_or_id) do
      revisions =
        from(r in WorkbookRevision,
          where: r.workbook_id == ^workbook.id,
          order_by: [desc: r.inserted_at]
        )
        |> Repo.all()

      {:ok, revisions}
    end
  end

  defp resolve_workbook(%User{} = user, %Workbook{} = workbook) do
    if workbook.user_id == user.id, do: {:ok, workbook}, else: {:error, :forbidden}
  end

  defp resolve_workbook(%User{} = user, id) when is_binary(id), do: get_workbook(user, id)

  defp insert_revision(workbook, sql) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %WorkbookRevision{}
    |> Ecto.Changeset.change(%{
      workbook_id: workbook.id,
      sql: sql,
      inserted_at: now
    })
    |> Repo.insert()
  end

  defp prune_revisions(workbook_id, limit) do
    keep_ids =
      from(r in WorkbookRevision,
        where: r.workbook_id == ^workbook_id,
        order_by: [desc: r.inserted_at],
        limit: ^limit,
        select: r.id
      )
      |> Repo.all()

    from(r in WorkbookRevision,
      where: r.workbook_id == ^workbook_id and r.id not in ^keep_ids
    )
    |> Repo.delete_all()

    :ok
  end

  defp stringify(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
