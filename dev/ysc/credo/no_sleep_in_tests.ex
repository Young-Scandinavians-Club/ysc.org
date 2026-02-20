defmodule Ysc.Credo.NoSleepInTests do
  use Credo.Check,
    id: "EX9001",
    base_priority: :high,
    category: :warning,
    param_defaults: [
      files: %{included: ["test/**/*.{ex,exs}"]}
    ],
    explanations: [
      check: """
      `Process.sleep/1` and `:timer.sleep/1` should be avoided in tests.

      Sleeps make the test suite slower and are usually a sign that the test
      is waiting for an async side-effect that can be handled more reliably:

        * **LiveView `start_async` / `assign_async`** – Use `render_async(view)`
          from `Phoenix.LiveViewTest`. It polls the LiveView process until all
          async tasks finish, with zero unnecessary delay:

              {:ok, view, _html} = live(conn, ~p"/my-route")
              render_async(view)
              assert render(view) =~ "Expected Content"

          After a PubSub broadcast, `render(view)` alone is sufficient because
          it already synchronises with the LiveView process.

        * **Oban jobs** – Oban runs in `testing: :inline` mode, so jobs execute
          synchronously. No sleep is needed before asserting on their results.

        * **Database propagation** – Ecto Sandbox transactions are synchronous.
          A `Repo.reload!/1` immediately after the operation is sufficient.

        * **PubSub / messaging** – Use `assert_receive` with a timeout instead
          of a fixed sleep.

        * **Timestamp ordering** – Set the `inserted_at` field explicitly on the
          changeset instead of sleeping between inserts:

              now = DateTime.utc_now() |> DateTime.truncate(:second)
              invite |> Ecto.Changeset.change(%{inserted_at: DateTime.add(now, -60, :second)}) |> Repo.update()

        * **Expiry / TTL tests** – Create records with `expires_at` already in
          the past rather than waiting for real time to pass:

              expires_at: DateTime.add(DateTime.utc_now(), -5, :second)

        * **Cache version timestamps** – Set the cache version to a past value
          before populating the cache, then `invalidate()` produces a different
          version without any wall-clock delay.

      If you genuinely need a wall-clock delay (e.g. testing TTL scheduler
      timing), add a comment explaining why and tag the test with `@tag :slow`.
      """
    ]

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta))
    |> Enum.reverse()
  end

  # Process.sleep(n)
  defp traverse(
         {{:., _meta, [{:__aliases__, _, [:Process]}, :sleep]}, meta, _args} = ast,
         issues,
         issue_meta
       ) do
    {ast, [issue_for(issue_meta, meta[:line], "Process.sleep/1") | issues]}
  end

  # :timer.sleep(n) — the Erlang form used throughout the codebase
  defp traverse(
         {{:., _meta, [:timer, :sleep]}, meta, _args} = ast,
         issues,
         issue_meta
       ) do
    {ast, [issue_for(issue_meta, meta[:line], ":timer.sleep/1") | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(issue_meta,
      message:
        "Avoid #{trigger} in tests — it slows the suite and masks async issues. " <>
          "Use render_async/2 for LiveView, assert_receive for PubSub, or backdate " <>
          "timestamps instead of sleeping. See `mix credo explain #{id()}` for details.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
