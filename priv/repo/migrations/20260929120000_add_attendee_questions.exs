defmodule Ysc.Repo.Migrations.AddAttendeeQuestions do
  use Ecto.Migration

  def change do
    alter table(:ticket_tiers) do
      # Admin-defined per-ticket questions asked at checkout
      # (see Ysc.Events.AttendeeQuestion).
      add :attendee_questions, :jsonb, null: false, default: fragment("'[]'::jsonb")
    end

    alter table(:ticket_details) do
      # Answers keyed by question id, each with a snapshot of the question's
      # label/type so exports survive later edits to the tier's questions.
      add :answers, :jsonb, null: false, default: fragment("'{}'::jsonb")
    end
  end
end
