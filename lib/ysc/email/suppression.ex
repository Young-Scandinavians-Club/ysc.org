defmodule Ysc.Email.Suppression do
  @moduledoc false

  import Ecto.Query

  alias Ysc.Repo

  @table "email_suppressions"

  def suppress_hard_bounce(email) when is_binary(email) do
    email = normalize_email(email)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(
      @table,
      [
        %{
          email: email,
          reason: "hard_bounce",
          suppressed_at: now,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: [
        set: [reason: "hard_bounce", suppressed_at: now, updated_at: now]
      ],
      conflict_target: :email
    )

    :ok
  end

  def hard_bounced?(email) when is_binary(email) do
    from(s in @table,
      where: s.email == ^normalize_email(email) and s.reason == "hard_bounce",
      select: 1
    )
    |> Repo.exists?()
  end

  def hard_bounced?(_), do: false

  defp normalize_email(email), do: email |> String.trim() |> String.downcase()
end
