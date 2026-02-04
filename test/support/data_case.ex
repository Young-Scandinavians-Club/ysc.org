defmodule Ysc.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Ysc.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Oban.Testing, repo: Ysc.Repo

      alias Ysc.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Ysc.DataCase
      import Mox
    end
  end

  setup tags do
    owner = Ysc.DataCase.setup_sandbox(tags)
    # Ensure basic site settings exist, unless the test explicitly opts out
    unless tags[:skip_settings_setup] do
      Ysc.Settings.ensure_settings_exist()
    end

    {:ok, sandbox_owner: owner}
  end

  @doc """
  Sets up the sandbox based on the test tags.
  Returns the owner PID so it can be passed to concurrent tasks.
  """
  def setup_sandbox(tags) do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Ysc.Repo, shared: not tags[:async])

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    pid
  end

  @doc """
  Allows a process to checkout its own database connection from the sandbox.
  This is necessary for concurrent tests using Task.async_stream where each
  task needs its own connection for proper database locking behavior.

  When async: true, you must pass the owner PID from the test context.
  When async: false, the owner is available from Repo.config()[:owner].
  """
  def allow_sandbox(pid \\ self(), owner \\ nil) do
    owner =
      owner || Ysc.Repo.config()[:owner] ||
        Process.get({Ecto.Adapters.SQL.Sandbox, :owner})

    if owner do
      Ecto.Adapters.SQL.Sandbox.allow(Ysc.Repo, pid, owner)
    else
      # Fallback: use checkout which finds the owner automatically from parent
      Ecto.Adapters.SQL.Sandbox.checkout(Ysc.Repo, sandbox: true)
    end
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
