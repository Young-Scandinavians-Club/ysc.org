defmodule QueryConsole.Runner.Lease do
  @moduledoc """
  Global single-active-query lease stored in the metadata database.
  """

  import Ecto.Query

  alias QueryConsole.Repo
  alias QueryConsole.Runner.QueryLease

  @global_holder "global"

  def acquire(query_run_id, opts \\ []) do
    ttl_ms =
      Keyword.get(
        opts,
        :ttl_ms,
        Application.get_env(:query_console, :query_lease_ttl_ms, 120_000)
      )

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = DateTime.add(now, div(ttl_ms, 1000), :second)

    Repo.transaction(fn ->
      expire_stale!(now)

      case Repo.get_by(QueryLease, holder: @global_holder) do
        nil ->
          insert_lease!(query_run_id, now, expires_at)

        %QueryLease{} = existing ->
          if DateTime.compare(existing.expires_at, now) == :lt do
            existing
            |> QueryLease.changeset(%{
              query_run_id: query_run_id,
              acquired_at: now,
              expires_at: expires_at
            })
            |> Repo.update!()
          else
            Repo.rollback(:lease_held)
          end
      end
    end)
  end

  def release(query_run_id) when is_binary(query_run_id) do
    from(l in QueryLease,
      where: l.holder == ^@global_holder and l.query_run_id == ^query_run_id
    )
    |> Repo.delete_all()

    :ok
  end

  def release_holder do
    from(l in QueryLease, where: l.holder == ^@global_holder)
    |> Repo.delete_all()

    :ok
  end

  def held? do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(QueryLease, holder: @global_holder) do
      nil -> false
      %QueryLease{expires_at: expires_at} -> DateTime.compare(expires_at, now) != :lt
    end
  end

  def current do
    Repo.get_by(QueryLease, holder: @global_holder)
  end

  defp expire_stale!(now) do
    from(l in QueryLease, where: l.expires_at < ^now)
    |> Repo.delete_all()
  end

  defp insert_lease!(query_run_id, now, expires_at) do
    %QueryLease{}
    |> QueryLease.changeset(%{
      holder: @global_holder,
      query_run_id: query_run_id,
      acquired_at: now,
      expires_at: expires_at
    })
    |> Repo.insert!()
  end
end
