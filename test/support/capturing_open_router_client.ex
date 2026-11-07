defmodule Ysc.Test.CapturingOpenRouterClient do
  @moduledoc false

  # Test double for `Ysc.OpenRouter` that sends the request to the calling
  # process (`assert_received {:chat, messages, config}`) and replies with the
  # response queued in `Process.put(:capturing_response, ...)`. Like
  # `ScriptedOpenRouterClient` it only works when the call happens in-process.
  def do_chat(messages, config) do
    send(self(), {:chat, messages, config})
    Process.get(:capturing_response, {:ok, ~s({"findings": []})})
  end
end
