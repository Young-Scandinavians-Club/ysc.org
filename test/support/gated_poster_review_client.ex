defmodule Ysc.Test.GatedPosterReviewClient do
  @moduledoc false

  # OpenRouter test double for mid-flight cover swaps. The LiveView async task
  # parks until the test process sends `{:poster_review_continue, rule}` so a
  # cancelled review can be released after a newer cover was picked.
  def do_chat(_messages, _config) do
    gate = Application.get_env(:ysc, :poster_review_gate)
    send(gate, {:poster_review_waiting, self()})

    rule =
      receive do
        {:poster_review_continue, rule} when is_binary(rule) -> rule
      after
        5_000 ->
          Application.get_env(:ysc, :poster_review_rule, "embedded_text")
      end

    {:ok,
     Jason.encode!(%{
       "findings" => [
         %{"rule" => rule, "detail" => "Gated mock finding for #{rule}"}
       ]
     })}
  end
end
