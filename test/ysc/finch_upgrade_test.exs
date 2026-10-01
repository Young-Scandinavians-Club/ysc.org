defmodule Ysc.FinchUpgradeTest do
  @moduledoc """
  Guards the finch 0.23.0 → 0.24.0 upgrade.

  0.24.0 is a minor with no documented breaking changes. It closes HTTP/1
  connections after request or response errors before returning them to
  the pool (stale Mint 1.11 refs after receive timeouts), closes discarded
  HTTP/1 connections asynchronously, waits for dynamically started HTTP/2
  pools within `:pool_timeout`, and adds the HTTP `QUERY` method.

  We use `Finch.build/4` + `Finch.request/2` from QuickBooks, Discord,
  Flowroute, and the outage scraper. We do not use `:query`,
  `Finch.start_pool/3`, or `SSLKEYLOGFILE`.
  """
  use ExUnit.Case, async: true

  alias Ysc.Alerts.DiscordHttpClient

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @changelog Path.expand("../../deps/finch/CHANGELOG.md", __DIR__)
  @conn Path.expand("../../deps/finch/lib/finch/http1/conn.ex", __DIR__)
  @http1_pool Path.expand("../../deps/finch/lib/finch/http1/pool.ex", __DIR__)
  @request Path.expand("../../deps/finch/lib/finch/request.ex", __DIR__)
  @application Path.expand("../../lib/ysc/application.ex", __DIR__)
  @discord_client Path.expand(
                    "../../lib/ysc/alerts/discord_http_client.ex",
                    __DIR__
                  )
  @quickbooks_client Path.expand(
                       "../../lib/ysc/quickbooks/client.ex",
                       __DIR__
                     )
  @flowroute_client Path.expand("../../lib/ysc/flowroute/client.ex", __DIR__)
  @outage_scraper Path.expand(
                    "../../lib/ysc/property_outages/scraper.ex",
                    __DIR__
                  )

  setup_all do
    {:ok, _} = Application.ensure_all_started(:finch)
    {:module, Finch} = Code.ensure_loaded(Finch)
    {:module, Finch.Request} = Code.ensure_loaded(Finch.Request)
    {:module, Finch.Response} = Code.ensure_loaded(Finch.Response)
    {:module, Finch.HTTP1.Conn} = Code.ensure_loaded(Finch.HTTP1.Conn)
    {:module, Finch.HTTP1.Pool} = Code.ensure_loaded(Finch.HTTP1.Pool)
    :ok
  end

  describe "0.24.0 Hex lock and public APIs" do
    test "locks the Hex package to 0.24.0" do
      assert to_string(Application.spec(:finch, :vsn)) == "0.24.0"
    end

    test "mix.exs pins the 0.24.0 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:finch, "~> 0.24.0"})
    end

    test "keeps mint 1.11.0 which 0.24.0 locks against" do
      assert to_string(Application.spec(:mint, :vsn)) == "1.11.0"
    end

    test "build and request APIs we use still exist" do
      {:module, Finch} = Code.ensure_loaded(Finch)
      {:module, Finch.Response} = Code.ensure_loaded(Finch.Response)
      assert function_exported?(Finch, :build, 2)
      assert function_exported?(Finch, :build, 3)
      assert function_exported?(Finch, :build, 4)
      assert function_exported?(Finch, :build, 5)
      assert function_exported?(Finch, :request, 2)
      assert function_exported?(Finch, :request, 3)
      assert function_exported?(Finch, :start_link, 1)
      refute function_exported?(Finch, :request, 6)
    end
  end

  describe "0.24.0 changelog" do
    test "documents the HTTP/1 close-after-error and QUERY additions" do
      changelog = File.read!(@changelog)

      v024 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "v0.24.0"))

      assert v024

      assert v024 =~
               "Close HTTP/1 connections after request or response errors"

      assert v024 =~ "stale response references"
      assert v024 =~ "Mint 1.11"
      assert v024 =~ "HTTP `QUERY` method"
      assert v024 =~ "Close discarded HTTP/1 connections asynchronously"
      refute v024 =~ "Breaking"
    end
  end

  describe "0.24.0 HTTP/1 close-after-error" do
    test "request errors close the mint connection before checkin" do
      source = File.read!(@conn)

      assert source =~
               "defp handle_request_error(conn, mint, error, acc, metadata, start_time, extra_measurements) do"

      assert source =~
               "{:error, close(%{conn | mint: mint}), wrapped_error, acc}"
    end

    test "response errors also close the mint connection" do
      source = File.read!(@conn)

      assert source =~
               "defp handle_response(response, conn, metadata, start_time, extra_measurements) do"

      assert source =~ "{:error, mint, error, acc, resp_metadata} ->"

      assert source =~
               "{:error, close(%{conn | mint: mint}), wrapped_error, acc}"
    end

    test "discarded HTTP/1 workers close asynchronously" do
      source = File.read!(@http1_pool)

      assert source =~
               "def terminate_worker(_reason, conn, %__MODULE__.State{} = pool_state) do"

      assert source =~ "spawn(fn -> Conn.close(conn) end)"
    end
  end

  describe "0.24.0 QUERY method is unused" do
    test "Finch.build accepts :query and encodes QUERY" do
      {:module, Finch} = Code.ensure_loaded(Finch)
      request = Finch.build(:query, "http://example.com/search")
      assert request.method == "QUERY"
    end

    test "request.ex lists :query next to GET" do
      source = File.read!(@request)
      assert source =~ ":query,"
      assert source =~ ~s("QUERY",)
    end

    test "app Finch call sites still use get and post only" do
      for path <- [
            @discord_client,
            @quickbooks_client,
            @flowroute_client,
            @outage_scraper
          ] do
        source = File.read!(path)
        refute source =~ "Finch.build(:query"
        refute source =~ "Finch.start_pool"
        assert source =~ "Finch.build("
        assert source =~ "Finch.request("
        assert source =~ "Ysc.Finch"
      end

      application = File.read!(@application)
      assert application =~ "{Finch, name: Ysc.Finch}"
    end
  end

  describe "runtime GET/POST through Ysc.Finch" do
    test "GET still returns Finch.Response status and body" do
      {result, req} =
        with_http1_server(
          "HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\nok",
          fn url ->
            request = Finch.build(:get, url)

            Finch.request(request, Ysc.Finch, receive_timeout: 1_000)
          end
        )

      assert {:ok, %Finch.Response{status: 200, body: "ok"}} = result
      assert req =~ "GET /"
    end

    test "POST still returns Finch.Response status and body" do
      {result, req} =
        with_http1_server(
          "HTTP/1.1 201 Created\r\ncontent-length: 7\r\n\r\ncreated",
          fn url ->
            request =
              Finch.build(
                :post,
                url,
                [{"content-type", "application/json"}],
                ~s|{"ok":true}|
              )

            Finch.request(request, Ysc.Finch, receive_timeout: 1_000)
          end
        )

      assert {:ok, %Finch.Response{status: 201, body: "created"}} = result
      assert req =~ "POST /"
    end

    test "DiscordHttpClient still posts through Finch.build/4 and request/2" do
      {result, req} =
        with_http1_server(
          "HTTP/1.1 204 No Content\r\ncontent-length: 0\r\n\r\n",
          fn url ->
            DiscordHttpClient.send_webhook(
              url,
              ~s|{"content":"finch-0.24"}|,
              [{"content-type", "application/json"}]
            )
          end
        )

      assert result == {:ok, :sent}
      assert req =~ "POST /"
    end

    test "a request after a closed HTTP/1 connection still succeeds" do
      {:ok, listen} =
        :gen_tcp.listen(0, [
          :binary,
          packet: :raw,
          active: false,
          reuseaddr: true
        ])

      {:ok, port} = :inet.port(listen)
      url = "http://127.0.0.1:#{port}/"
      request = Finch.build(:get, url)

      closer =
        Task.async(fn ->
          {:ok, client} = :gen_tcp.accept(listen, 5_000)
          _ = :gen_tcp.recv(client, 0, 5_000)
          :gen_tcp.close(client)
        end)

      assert {:error, _reason} =
               Finch.request(request, Ysc.Finch, receive_timeout: 500)

      _ = Task.await(closer, 5_000)

      responder =
        Task.async(fn ->
          {:ok, client} = :gen_tcp.accept(listen, 5_000)
          _ = :gen_tcp.recv(client, 0, 5_000)

          :ok =
            :gen_tcp.send(
              client,
              "HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\nok"
            )

          :gen_tcp.close(client)
          :gen_tcp.close(listen)
        end)

      assert {:ok, %Finch.Response{status: 200, body: "ok"}} =
               Finch.request(request, Ysc.Finch, receive_timeout: 1_000)

      _ = Task.await(responder, 5_000)
    end
  end

  defp with_http1_server(response, fun) do
    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen)

    server =
      Task.async(fn ->
        {:ok, client} = :gen_tcp.accept(listen, 5_000)
        {:ok, req} = :gen_tcp.recv(client, 0, 5_000)
        :ok = :gen_tcp.send(client, response)
        :gen_tcp.close(client)
        :gen_tcp.close(listen)
        req
      end)

    result = fun.("http://127.0.0.1:#{port}/")
    {result, Task.await(server, 5_000)}
  end
end
