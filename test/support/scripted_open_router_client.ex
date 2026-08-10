defmodule Ysc.Test.ScriptedOpenRouterClient do
  @moduledoc false

  # Test double for `Ysc.OpenRouter` that pops a queued response per call, so
  # a test can script exactly what each chat turn (finder / locate / clarify /
  # follow-up) returns. Responses live in the *process dictionary* of the
  # calling test process — `Assistant` calls this synchronously in-process
  # (no spawn), so `Process.put/2` from the test body is visible here.
  def do_chat(_messages, _config) do
    case Process.get(:scripted_responses) do
      [next | rest] ->
        Process.put(:scripted_responses, rest)
        next

      _ ->
        {:ok, Jason.encode!(%{"answer" => "fallback", "suggested_step" => nil})}
    end
  end
end
