defmodule Ysc.Accounts.FamilyMembers do
  @moduledoc """
  Context for family member records on a user's account.
  """
  require Ysc.Logging

  alias Ysc.Repo
  alias Ysc.Accounts.{FamilyMember, User, UserProfileCache}

  @doc """
  Returns family members for a user, preloading when needed.
  """
  def list_for_user(%User{} = user) do
    case user.family_members do
      %Ecto.Association.NotLoaded{} ->
        user |> Repo.preload(:family_members) |> Map.get(:family_members) || []

      members when is_list(members) ->
        members

      _ ->
        []
    end
  end

  @doc """
  Finds a family member by ID for the given user.
  """
  def find_by_id(_user, id) when id in [nil, ""], do: nil

  def find_by_id(%User{} = user, id) do
    user
    |> list_for_user()
    |> Enum.find(&(to_string(&1.id) == to_string(id)))
  end

  @doc """
  Converts form params into attrs for `FamilyMember.family_member_changeset/2`.
  """
  def record_attrs(params) when is_map(params) do
    relationship_str = params["relationship"] || "child"
    birth_date = params["birth_date"]

    type =
      case relationship_str do
        "spouse" -> :spouse
        _ -> :child
      end

    %{
      "first_name" => String.trim(params["first_name"] || ""),
      "last_name" => String.trim(params["last_name"] || ""),
      "type" => type,
      "birth_date" => if(birth_date in [nil, ""], do: nil, else: birth_date),
      "email" => String.trim(params["email"] || "")
    }
  end

  @doc """
  Builds a changeset for live form validation.
  """
  def changeset_for_params(%User{} = user, params) when is_map(params) do
    user
    |> struct_for_params(params)
    |> FamilyMember.family_member_changeset(record_attrs(params))
  end

  @doc """
  Validates family member params without persisting.
  """
  def validate_params(%User{} = user, params) when is_map(params) do
    user
    |> changeset_for_params(params)
    |> Ecto.Changeset.apply_action(:insert)
    |> case do
      {:ok, _} -> {:ok, params}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Creates or updates a family member for the user.

  Updates only when `params["id"]` matches an existing record; otherwise inserts a new one.
  Invalidates the user profile cache so subsequent preloads see the change.
  """
  def upsert_family_member(%User{} = user, params) when is_map(params) do
    attrs = record_attrs(params)

    result =
      case find_by_id(user, params["id"]) do
        %FamilyMember{} = member ->
          member
          |> FamilyMember.family_member_changeset(attrs)
          |> Repo.update()

        nil ->
          %FamilyMember{}
          |> FamilyMember.family_member_changeset(attrs)
          |> Ecto.Changeset.put_change(:user_id, user.id)
          |> Repo.insert()
      end

    case result do
      {:ok, member} ->
        UserProfileCache.invalidate_user(user.id)
        {:ok, member}

      error ->
        error
    end
  end

  @doc """
  Deletes a family member belonging to the user and invalidates the profile cache.
  """
  def delete_family_member(
        %User{id: user_id},
        %FamilyMember{user_id: user_id} = member
      ) do
    case Repo.delete(member, allow_stale: true) do
      {:ok, deleted} ->
        UserProfileCache.invalidate_user(user_id)
        {:ok, deleted}

      error ->
        error
    end
  end

  def delete_family_member(%User{}, %FamilyMember{}),
    do: {:error, :unauthorized}

  @doc """
  Deletes family members not present in `kept_ids`.
  """
  def delete_removed_members(%User{} = user, kept_ids)
      when is_struct(kept_ids, MapSet) do
    deleted? =
      Enum.reduce(list_for_user(user), false, fn member, acc ->
        if MapSet.member?(kept_ids, to_string(member.id)) do
          acc
        else
          case Repo.delete(member, allow_stale: true) do
            {:ok, _} ->
              true

            {:error, reason} ->
              Ysc.Logging.warning(
                "Failed to delete removed family member",
                user_id: user.id,
                family_member_id: member.id,
                reason: inspect(reason)
              )

              acc
          end
        end
      end)

    if deleted?, do: UserProfileCache.invalidate_user(user.id)

    :ok
  end

  defp struct_for_params(%User{} = user, params) do
    find_by_id(user, params["id"]) || %FamilyMember{}
  end
end
