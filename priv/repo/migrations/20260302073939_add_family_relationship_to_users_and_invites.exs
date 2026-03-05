defmodule Ysc.Repo.Migrations.AddFamilyRelationshipToUsersAndInvites do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :family_relationship, :string
    end

    alter table(:family_invites) do
      add :relationship, :string, null: false, default: "child"
    end
  end
end
