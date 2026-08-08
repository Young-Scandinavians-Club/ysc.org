defmodule QueryConsole.Accounts do
  @moduledoc """
  Local shadow users keyed by YSC user IDs and simple session helpers.
  """

  import Ecto.Query

  alias QueryConsole.Accounts.User
  alias QueryConsole.Repo

  @doc """
  Upserts a local user from SSO claims.

  Expected claim keys (string or atom):
  - `ysc_user_id` / `sub` / `id`
  - `email`
  - `display_name` / `name`
  - `role` (must be `"admin"`)
  """
  def upsert_from_sso(claims) when is_map(claims) do
    ysc_user_id = claim(claims, ["ysc_user_id", "sub", "id"])
    email = claim(claims, ["email"])
    display_name = claim(claims, ["display_name", "name"]) || email
    role = claim(claims, ["role"]) || "admin"
    state = claim(claims, ["state"])

    cond do
      is_nil(ysc_user_id) or ysc_user_id == "" ->
        {:error, :missing_ysc_user_id}

      is_nil(email) or email == "" ->
        {:error, :missing_email}

      role != "admin" ->
        {:error, :not_admin}

      is_binary(state) and state != "active" ->
        {:error, :not_active}

      true ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        attrs = %{
          ysc_user_id: to_string(ysc_user_id),
          email: to_string(email),
          display_name: to_string(display_name),
          role: "admin",
          last_login_at: now
        }

        case get_user_by_ysc_id(attrs.ysc_user_id) do
          nil ->
            %User{}
            |> User.changeset(attrs)
            |> Repo.insert()

          user ->
            user
            |> User.changeset(attrs)
            |> Repo.update()
        end
    end
  end

  def get_user(id) when is_binary(id), do: Repo.get(User, id)

  def get_user_by_ysc_id(ysc_user_id) when is_binary(ysc_user_id) do
    Repo.get_by(User, ysc_user_id: ysc_user_id)
  end

  def list_users do
    from(u in User, order_by: [asc: u.email]) |> Repo.all()
  end

  defp claim(map, keys) do
    Enum.find_value(keys, fn key ->
      Map.get(map, key) || claim_alt(map, key)
    end)
  end

  defp claim_alt(map, key) when is_binary(key) do
    try do
      Map.get(map, String.to_existing_atom(key))
    rescue
      ArgumentError -> nil
    end
  end

  defp claim_alt(map, key) when is_atom(key), do: Map.get(map, Atom.to_string(key))
  defp claim_alt(_map, _key), do: nil
end
