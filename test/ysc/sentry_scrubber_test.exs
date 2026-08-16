defmodule Ysc.SentryScrubberTest do
  use ExUnit.Case, async: true

  alias Ysc.SentryScrubber

  describe "scrub_url/1" do
    test "redacts default and auth-related query parameters" do
      conn =
        Plug.Test.conn(
          :get,
          "/users/log-in/auto?token=secret-login-token&setup_token=setup-abc&password=hunter2&code=oauth-code"
        )

      url = SentryScrubber.scrub_url(conn)
      query = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      refute url =~ "secret-login-token"
      refute url =~ "setup-abc"
      refute url =~ "hunter2"
      refute url =~ "oauth-code"
      assert query["token"] == Sentry.Scrubber.scrubbed_value()
      assert query["setup_token"] == Sentry.Scrubber.scrubbed_value()
      assert query["password"] == Sentry.Scrubber.scrubbed_value()
      assert query["code"] == Sentry.Scrubber.scrubbed_value()
    end

    test "leaves non-sensitive query parameters unchanged" do
      conn = Plug.Test.conn(:get, "/events?filter=upcoming&page=2")

      assert SentryScrubber.scrub_url(conn) ==
               "http://www.example.com/events?filter=upcoming&page=2"
    end

    test "redacts the FlowRoute webhook token from the URL path" do
      conn =
        Plug.Test.conn(
          :post,
          "/webhooks/flowroute/super-secret-webhook-token/sms_dlr"
        )

      url = SentryScrubber.scrub_url(conn)

      refute url =~ "super-secret-webhook-token"
      assert url =~ "/webhooks/flowroute/[REDACTED]/sms_dlr"
    end
  end

  describe "scrub_params/1" do
    test "redacts sensitive form fields" do
      conn =
        Plug.Test.conn(:post, "/users/log-in", %{
          "email" => "user@example.com",
          "password" => "hunter2",
          "token" => "one-time-token"
        })

      params = SentryScrubber.scrub_params(conn)

      assert params["email"] == "user@example.com"
      assert params["password"] == Sentry.Scrubber.scrubbed_value()
      assert params["token"] == Sentry.Scrubber.scrubbed_value()
    end
  end
end
