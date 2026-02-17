defmodule Ysc.Repo.Migrations.AddTicketsTbdToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      add :tickets_tbd, :boolean, default: false, null: false
    end
  end
end
