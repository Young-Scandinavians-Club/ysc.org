defmodule YscWeb.EndpointRequestLogTest do
  use ExUnit.Case, async: true

  import Plug.Test

  describe "request_log_level/1" do
    test "suppresses request lines for webhooks that carry a secret in the path" do
      for path <- [
            "/webhooks/flowroute/secret/sms",
            "/webhooks/flowroute/secret/mms_dlr",
            "/webhooks/printful/secret",
            # percent-encoded provider segment still routes to the webhook
            "/webhooks/%66lowroute/secret/sms",
            "/webhooks/%70rintful/secret"
          ] do
        refute YscWeb.Endpoint.request_log_level(conn(:post, path))
      end
    end

    test "logs everything else" do
      for path <- ["/", "/webhooks/ses", "/users/log-in"] do
        assert YscWeb.Endpoint.request_log_level(conn(:get, path)) == :info
      end
    end
  end
end
