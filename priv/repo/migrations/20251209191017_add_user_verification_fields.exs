defmodule Ysc.Repo.Migrations.AddUserVerificationFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :email_verified_at, :utc_datetime
      add :phone_verified_at, :utc_datetime
      add :password_set_at, :utc_datetime
    end
  end
end
