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
      `Process.sleep/1` should be avoided in tests.

      Sleeps make the test suite slower and are usually a sign that the test
      is waiting for an async side-effect that can be handled more reliably:

        * **Oban jobs** – Oban runs in `testing: :inline` mode, so jobs execute
          synchronously. No sleep is needed before asserting on their results.
        * **LiveView async assigns** – Use `assert_async/2` or a small
          `receive`-based helper that polls until the condition is met.
        * **Database propagation** – Ecto Sandbox transactions are synchronous.
          A `Repo.reload!/1` immediately after the operation is sufficient.
        * **PubSub / messaging** – Use `assert_receive` with a timeout instead
          of a fixed sleep.
        * **Cache version timestamps** – Set the cache version to a past value
          before populating the cache, then `invalidate()` produces a different
          version without any wall-clock delay.

      If you genuinely need a wall-clock delay (e.g. testing TTL expiry), add
      a comment explaining why and tag the test with `@tag :slow`.
      """
    ]

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta))
    |> Enum.reverse()
  end

  defp traverse(
         {{:., _meta, [{:__aliases__, _, [:Process]}, :sleep]}, meta, _args} =
           ast,
         issues,
         issue_meta
       ) do
    new_issue = issue_for(issue_meta, meta[:line], "Process.sleep/1")
    {ast, [new_issue | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(issue_meta,
      message:
        "Avoid #{trigger} in tests — it slows the suite and masks async issues. " <>
          "See `mix credo explain #{id()}` for alternatives.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
