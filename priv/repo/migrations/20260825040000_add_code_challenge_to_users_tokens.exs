defmodule Ysc.Repo.Migrations.AddCodeChallengeToUsersTokens do
  use Ecto.Migration

  def change do
    # Binds a "mobile_redirect" one-time code to the mobile app instance that
    # requested it (PKCE-style), so a different app that manages to intercept
    # the code via a custom-scheme collision still can't redeem it — see
    # Ysc.Accounts.generate_mobile_redirect_token/2. Only ever set for that
    # one context; null for every other token type.
    alter table(:users_tokens) do
      add :code_challenge, :string
    end
  end
end
