defmodule QueryConsole.ReqLlmUpgradeTest do
  @moduledoc """
  Guards the req_llm 1.17.1 → 1.29.0 override.

  1.29.0 is a security release for EEF-CVE-2026-107685 (CRITICAL /
  GHSA-6vww-5m28-f26v). OpenAI Responses, Realtime, and Codex
  WebSocket sessions now set `insecure: false` and pass
  `ssl_options` with `verify: :verify_peer`, system CAs, and hostname
  checks. 1.9.0 through 1.28.0 inherited WebSockex's `insecure: true`
  default (`verify: :verify_none`), so an on-path attacker could read
  the bearer token. HTTP streaming through Finch still verifies TLS.

  lotus lists `req_llm ~> 1.6`, so mix.exs pins 1.29.0 as an override.
  Query Console only turns on Lotus AI when `OPENROUTER_API_KEY` is set
  (OpenRouter HTTP). We do not set `openai_stream_transport` or call
  `start_responses_session/2` / `Realtime.connect/2`. Default transport
  remains `:sse`.

  Public Lotus APIs are unchanged: `ReqLLM.generate_text/3`,
  `ReqLLM.Context`, `ReqLLM.Response.text/usage/classify`,
  `ReqLLM.tool/1`, and `%ReqLLM.Error.API.Request{}`.
  """
  use ExUnit.Case, async: false

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/req_llm/CHANGELOG.md", __DIR__)
  @runtime Path.expand("../../config/runtime.exs", __DIR__)
  @ws_client Path.expand(
               "../../deps/req_llm/lib/req_llm/streaming/web_socket_session/client.ex",
               __DIR__
             )
  @ws_session Path.expand(
                "../../deps/req_llm/lib/req_llm/streaming/web_socket_session.ex",
                __DIR__
              )
  @transport Path.expand("../../deps/req_llm/lib/req_llm/transport.ex", __DIR__)
  @openai_provider Path.expand(
                     "../../deps/req_llm/lib/req_llm/providers/openai.ex",
                     __DIR__
                   )

  setup_all do
    {:ok, _} = Application.ensure_all_started(:req_llm)
    {:ok, _} = Application.ensure_all_started(:lotus)
    {:ok, _} = Application.ensure_all_started(:ssl)
    {:module, ReqLLM} = Code.ensure_loaded(ReqLLM)
    {:module, ReqLLM.Context} = Code.ensure_loaded(ReqLLM.Context)
    {:module, ReqLLM.Response} = Code.ensure_loaded(ReqLLM.Response)
    {:module, ReqLLM.Tool} = Code.ensure_loaded(ReqLLM.Tool)
    {:module, ReqLLM.Error.API.Request} = Code.ensure_loaded(ReqLLM.Error.API.Request)

    {:module, ReqLLM.Streaming.WebSocketSession.Client} =
      Code.ensure_loaded(ReqLLM.Streaming.WebSocketSession.Client)

    {:module, Lotus.AI.Error} = Code.ensure_loaded(Lotus.AI.Error)
    :ok
  end

  describe "1.29.0 Hex lock and public APIs" do
    test "locks the Hex package to 1.29.0" do
      assert to_string(Application.spec(:req_llm, :vsn)) == "1.29.0"
    end

    test "mix.exs pins the 1.29.0 floor override" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:req_llm, "~> 1.29.0", override: true})
    end

    test "companion lock is 1.29.0 and HTTP extras stay put" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"req_llm": {:hex, :req_llm, "1.29.0"|
      refute lock =~ ~s|"req_llm": {:hex, :req_llm, "1.17.1"|
      assert lock =~ ~s|"finch": {:hex, :finch, "0.24.0"|
      assert lock =~ ~s|"mint": {:hex, :mint, "1.11.0"|
      assert lock =~ ~s|"req": {:hex, :req, "0.7.5"|
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.0.4"|
      assert lock =~ ~s|"bandit": {:hex, :bandit, "1.14.1"|
    end

    test "required extras match req_llm 1.29.0" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"llm_db": {:hex, :llm_db, "2026.10.7"|
      assert lock =~ ~s|"zoi": {:hex, :zoi, "0.18.11"|
      assert lock =~ ~s|"jsv": {:hex, :jsv, "0.26.1"|
      assert lock =~ ~s|"dotenvy": {:hex, :dotenvy, "1.2.1"|
      assert lock =~ ~s|"splode": {:hex, :splode, "0.3.3"|
      assert lock =~ ~s|"texture": {:hex, :texture, "2.0.0"|
    end

    test "Lotus AI APIs still exist" do
      {:module, ReqLLM} = Code.ensure_loaded(ReqLLM)
      {:module, ReqLLM.Context} = Code.ensure_loaded(ReqLLM.Context)
      {:module, ReqLLM.Response} = Code.ensure_loaded(ReqLLM.Response)
      {:module, Lotus.AI.Error} = Code.ensure_loaded(Lotus.AI.Error)

      assert function_exported?(ReqLLM, :generate_text, 2)
      assert function_exported?(ReqLLM, :generate_text, 3)
      assert function_exported?(ReqLLM, :tool, 1)
      assert function_exported?(ReqLLM.Context, :new, 1)
      assert function_exported?(ReqLLM.Context, :system, 1)
      assert function_exported?(ReqLLM.Context, :user, 1)
      assert function_exported?(ReqLLM.Context, :assistant, 1)
      assert function_exported?(ReqLLM.Context, :to_list, 1)
      assert function_exported?(ReqLLM.Context, :execute_and_append_tools, 3)
      assert function_exported?(ReqLLM.Response, :text, 1)
      assert function_exported?(ReqLLM.Response, :usage, 1)
      assert function_exported?(ReqLLM.Response, :classify, 1)
      assert function_exported?(Lotus.AI.Error, :wrap, 1)
    end
  end

  describe "1.29.0 changelog" do
    test "documents TLS verification and has no Breaking heading" do
      changelog = File.read!(@changelog)

      v129 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "[1.29.0]"))

      assert v129
      assert v129 =~ "streaming: verify TLS for HTTPS WebSocket URLs"
      refute v129 =~ "Breaking"
    end
  end

  describe "1.29.0 TLS verification source" do
    test "WebSocket client sets insecure false and verify_peer" do
      source = File.read!(@ws_client)
      assert source =~ "Keyword.put(:insecure, false)"
      assert source =~ "verify: :verify_peer"
      assert source =~ ":public_key.cacerts_get()"
      assert source =~ "pkix_verify_hostname_match_fun(:https)"
      refute source =~ "verify: :verify_none"
    end

    test "session forwards cacerts and ssl_options to the client" do
      source = File.read!(@ws_session)
      assert source =~ "Keyword.take(opts, [:cacerts, :ssl_options])"
    end

    test "OpenAI streaming still defaults to SSE HTTP" do
      source = File.read!(@openai_provider)
      assert source =~ "openai_stream_transport:"
      assert source =~ "default: :sse"
      assert source =~ "Keyword.get(provider_opts, :openai_stream_transport, :sse)"
    end

    test "HTTP transport disables redirects by default" do
      source = File.read!(@transport)
      assert source =~ "redirect: Map.get(request.options, :redirect, false)"
    end
  end

  describe "Query Console usage stays on OpenRouter HTTP" do
    test "runtime enables Lotus AI via OpenRouter, not OpenAI WebSocket" do
      runtime = File.read!(@runtime)
      assert runtime =~ "OPENROUTER_API_KEY"

      assert runtime =~
               ~s[model: System.get_env("LOTUS_AI_MODEL") || "openrouter:moonshotai/kimi-k3"]

      refute runtime =~ "openai_stream_transport"
      refute runtime =~ "start_responses_session"
      refute runtime =~ "Realtime"
    end
  end

  describe "Lotus Context / tool / error wrappers still work" do
    test "Context constructors and to_list round-trip" do
      messages = [
        ReqLLM.Context.system("You are a SQL assistant"),
        ReqLLM.Context.user("list tables"),
        ReqLLM.Context.assistant("SELECT 1")
      ]

      context = ReqLLM.Context.new(messages)
      listed = ReqLLM.Context.to_list(context)
      assert length(listed) == 3
      assert Enum.map(listed, & &1.role) == [:system, :user, :assistant]
    end

    test "tool/1 still accepts lotus-style parameter_schema maps" do
      tool =
        ReqLLM.tool(
          name: "get_table_schema",
          description: "Return columns for a table",
          parameter_schema: %{
            "type" => "object",
            "properties" => %{
              "table" => %{"type" => "string", "description" => "Table name"}
            },
            "required" => ["table"]
          },
          callback: fn args -> {:ok, inspect(args)} end
        )

      assert tool.name == "get_table_schema"
      assert {:ok, result} = ReqLLM.Tool.execute(tool, %{"table" => "users"})
      assert is_binary(result)
    end

    test "execute_and_append_tools still runs a lotus-style tool call" do
      tool =
        ReqLLM.tool(
          name: "echo",
          description: "Echo arguments",
          parameter_schema: %{
            "type" => "object",
            "properties" => %{"value" => %{"type" => "string"}},
            "required" => ["value"]
          },
          callback: fn args -> {:ok, args["value"]} end
        )

      context = ReqLLM.Context.new([ReqLLM.Context.user("hi")])

      updated =
        ReqLLM.Context.execute_and_append_tools(
          context,
          [%{id: "call_1", name: "echo", arguments: %{"value" => "pong"}}],
          [tool]
        )

      roles = updated |> ReqLLM.Context.to_list() |> Enum.map(& &1.role)
      assert :tool in roles
    end

    test "Lotus.AI.Error.wrap still matches Request status and timeout reason" do
      assert %Lotus.AI.Error.RateLimitError{} =
               Lotus.AI.Error.wrap(%ReqLLM.Error.API.Request{status: 429, reason: "rate limited"})

      assert %Lotus.AI.Error.AuthenticationError{} =
               Lotus.AI.Error.wrap(%ReqLLM.Error.API.Request{status: 401, reason: "unauthorized"})

      assert %Lotus.AI.Error.ServerError{} =
               Lotus.AI.Error.wrap(%ReqLLM.Error.API.Request{status: 503, reason: "unavailable"})

      assert %Lotus.AI.Error.TimeoutError{} =
               Lotus.AI.Error.wrap(%ReqLLM.Error.API.Request{reason: "timed out"})

      assert %Lotus.AI.Error.ServiceError{} =
               Lotus.AI.Error.wrap(%ReqLLM.Error.API.Request{reason: "something else"})
    end
  end

  describe "1.29.0 untrusted WebSocket certificate is rejected" do
    test "wss handshake to a self-signed listener does not connect" do
      {listen, url} = start_self_signed_wss_listener()

      result =
        ReqLLM.Streaming.WebSocketSession.Client.start(url, self(),
          socket_connect_timeout: 2_000,
          socket_recv_timeout: 2_000
        )

      refute_receive {:web_socket_session, _pid, :connected}, 1_000

      case result do
        {:error, _reason} ->
          :ok

        {:ok, pid} ->
          assert_receive {:web_socket_session, ^pid, {:disconnected, _reason}}, 2_000
      end

      _ = :ssl.close(listen)
    end
  end

  defp start_self_signed_wss_listener do
    tmp = System.tmp_dir!()
    unique = System.unique_integer([:positive])
    key = Path.join(tmp, "req-llm-upgrade-#{unique}-key.pem")
    cert = Path.join(tmp, "req-llm-upgrade-#{unique}-cert.pem")

    {_, 0} =
      System.cmd("openssl", [
        "req",
        "-x509",
        "-newkey",
        "rsa:2048",
        "-keyout",
        key,
        "-out",
        cert,
        "-days",
        "1",
        "-nodes",
        "-subj",
        "/CN=localhost"
      ])

    {:ok, listen} =
      :ssl.listen(0, [
        :binary,
        certfile: String.to_charlist(cert),
        keyfile: String.to_charlist(key),
        reuseaddr: true,
        active: false
      ])

    {:ok, {_addr, port}} = :ssl.sockname(listen)

    spawn(fn ->
      case :ssl.transport_accept(listen, 5_000) do
        {:ok, sock} ->
          _ = :ssl.handshake(sock, 5_000)
          _ = :ssl.close(sock)

        _ ->
          :ok
      end
    end)

    {listen, "wss://127.0.0.1:#{port}/"}
  end
end
