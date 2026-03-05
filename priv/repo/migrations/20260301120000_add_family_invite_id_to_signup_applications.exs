defmodule Ysc.Repo.Migrations.AddFamilyInviteIdToSignupApplications do
  use Ecto.Migration

  def change do
    alter table(:signup_applications) do
      add :family_invite_id, references(:family_invites, type: :binary_id, on_delete: :nilify_all),
        null: true
    end

    create index(:signup_applications, [:family_invite_id])
  end
end
