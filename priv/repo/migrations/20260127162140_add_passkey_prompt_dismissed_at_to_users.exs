defmodule Ysc.Repo.Migrations.AddPasskeyPromptDismissedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :passkey_prompt_dismissed_at, :utc_datetime, null: true
    end
  end
end
