defmodule Ysc.StripityStripeUpgradeTest do
  @moduledoc """
  Guards the stripity_stripe 3.3.2 → 3.3.3 upgrade.

  3.3.3 is a patch with no lib/ changes. It requires hackney `~> 4.9`
  for that client's security fixes, plus a CI common-config sync. We
  already override hackney at 4.10.2 and route Stripe HTTP through
  `Ysc.Stripe.HttpClient` (Req) because stripity_stripe's default
  hackney adapter used to send `Connection: keep-alive`, which hackney
  4.x rejects with `:protocol_error`. Public Stripe.* APIs we call are
  unchanged. extras: none (telemetry stayed 1.4.2; hackney 4.10.2).
  """
  use ExUnit.Case, async: true

  alias Ysc.Stripe.HttpClient
  alias Ysc.StripeClient

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/stripity_stripe/CHANGELOG.md", __DIR__)
  @stripe_mix Path.expand("../../deps/stripity_stripe/mix.exs", __DIR__)
  @api Path.expand("../../deps/stripity_stripe/lib/stripe/api.ex", __DIR__)
  @webhook_plug Path.expand(
                  "../../deps/stripity_stripe/lib/stripe/webhook_plug.ex",
                  __DIR__
                )
  @http_client Path.expand("../../lib/ysc/stripe/http_client.ex", __DIR__)
  @stripe_client Path.expand("../../lib/ysc/stripe_client.ex", __DIR__)
  @endpoint Path.expand("../../lib/ysc_web/endpoint.ex", __DIR__)
  @application Path.expand("../../lib/ysc/application.ex", __DIR__)
  @config Path.expand("../../config/config.exs", __DIR__)
  @runtime Path.expand("../../config/runtime.exs", __DIR__)
  @subscriptions Path.expand("../../lib/ysc/subscriptions.ex", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:stripity_stripe)
    {:module, Stripe} = Code.ensure_loaded(Stripe)
    {:module, Stripe.API} = Code.ensure_loaded(Stripe.API)
    {:module, Stripe.Config} = Code.ensure_loaded(Stripe.Config)
    {:module, Stripe.Converter} = Code.ensure_loaded(Stripe.Converter)
    {:module, Stripe.Error} = Code.ensure_loaded(Stripe.Error)
    {:module, Stripe.Webhook} = Code.ensure_loaded(Stripe.Webhook)
    {:module, Stripe.WebhookPlug} = Code.ensure_loaded(Stripe.WebhookPlug)
    {:module, Stripe.WebhookHandler} = Code.ensure_loaded(Stripe.WebhookHandler)
    {:module, Stripe.Customer} = Code.ensure_loaded(Stripe.Customer)
    {:module, Stripe.Subscription} = Code.ensure_loaded(Stripe.Subscription)

    {:module, Stripe.SubscriptionSchedule} =
      Code.ensure_loaded(Stripe.SubscriptionSchedule)

    {:module, Stripe.PaymentIntent} = Code.ensure_loaded(Stripe.PaymentIntent)
    {:module, Stripe.PaymentMethod} = Code.ensure_loaded(Stripe.PaymentMethod)
    {:module, Stripe.SetupIntent} = Code.ensure_loaded(Stripe.SetupIntent)
    {:module, Stripe.Invoice} = Code.ensure_loaded(Stripe.Invoice)
    {:module, Stripe.InvoicePayment} = Code.ensure_loaded(Stripe.InvoicePayment)
    {:module, Stripe.Refund} = Code.ensure_loaded(Stripe.Refund)
    {:module, Stripe.Charge} = Code.ensure_loaded(Stripe.Charge)
    {:module, Stripe.Payout} = Code.ensure_loaded(Stripe.Payout)

    {:module, Stripe.BalanceTransaction} =
      Code.ensure_loaded(Stripe.BalanceTransaction)

    {:module, Stripe.Event} = Code.ensure_loaded(Stripe.Event)
    {:module, Stripe.PaymentLink} = Code.ensure_loaded(Stripe.PaymentLink)

    {:module, Stripe.Checkout.Session} =
      Code.ensure_loaded(Stripe.Checkout.Session)

    {:module, Stripe.Terminal.ConnectionToken} =
      Code.ensure_loaded(Stripe.Terminal.ConnectionToken)

    {:module, HttpClient} = Code.ensure_loaded(HttpClient)
    {:module, StripeClient} = Code.ensure_loaded(StripeClient)

    {:module, Ysc.Stripe.WebhookHandler} =
      Code.ensure_loaded(Ysc.Stripe.WebhookHandler)

    :ok
  end

  describe "3.3.3 Hex lock and public APIs" do
    test "locks the Hex package to 3.3.3" do
      assert to_string(Application.spec(:stripity_stripe, :vsn)) == "3.3.3"
    end

    test "mix.exs pins the 3.3.3 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|{:stripity_stripe, "~> 3.3.3"}|
      refute mix_exs =~ ~s|{:stripity_stripe, "~> 3.3"}|
    end

    test "companion lock is 3.3.3 and extras stay put" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"stripity_stripe": {:hex, :stripity_stripe, "3.3.3"|
      refute lock =~ ~s|"stripity_stripe": {:hex, :stripity_stripe, "3.3.2"|
      assert lock =~ ~s|"hackney": {:hex, :hackney, "4.10.2"|
      assert lock =~ ~s|"telemetry": {:hex, :telemetry, "1.4.2"|
      refute lock =~ ~s|"telemetry": {:hex, :telemetry, "1.4.3"|
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.0.4"|
      assert lock =~ ~s|"uri_query": {:hex, :uri_query, "0.2.0"|
    end

    test "stripity_stripe requires hackney 4.9 as the floor" do
      stripe_mix = File.read!(@stripe_mix)
      assert stripe_mix =~ ~s|{:hackney, "~> 4.9"}|
      refute stripe_mix =~ ~s|{:hackney, "~> 4.0"}|
    end

    test "resource APIs we call still exist" do
      assert function_exported?(Stripe.Customer, :create, 1)
      assert function_exported?(Stripe.Customer, :update, 2)
      assert function_exported?(Stripe.Subscription, :create, 1)
      assert function_exported?(Stripe.Subscription, :retrieve, 1)
      assert function_exported?(Stripe.Subscription, :update, 2)
      assert function_exported?(Stripe.Subscription, :cancel, 1)
      assert function_exported?(Stripe.SubscriptionSchedule, :create, 1)
      assert function_exported?(Stripe.SubscriptionSchedule, :retrieve, 1)
      assert function_exported?(Stripe.SubscriptionSchedule, :update, 2)
      assert function_exported?(Stripe.SubscriptionSchedule, :release, 1)
      assert function_exported?(Stripe.PaymentIntent, :create, 2)
      assert function_exported?(Stripe.PaymentIntent, :retrieve, 2)
      assert function_exported?(Stripe.PaymentIntent, :cancel, 2)
      assert function_exported?(Stripe.PaymentMethod, :retrieve, 1)
      assert function_exported?(Stripe.PaymentMethod, :attach, 2)
      assert function_exported?(Stripe.SetupIntent, :create, 1)
      assert function_exported?(Stripe.Invoice, :retrieve, 2)
      assert function_exported?(Stripe.InvoicePayment, :list, 1)
      assert function_exported?(Stripe.Refund, :create, 1)
      assert function_exported?(Stripe.Charge, :retrieve, 2)
      assert function_exported?(Stripe.Payout, :retrieve, 2)
      assert function_exported?(Stripe.BalanceTransaction, :list, 1)
      assert function_exported?(Stripe.Event, :list, 2)
      assert function_exported?(Stripe.PaymentLink, :retrieve, 1)
      assert function_exported?(Stripe.Checkout.Session, :create, 1)
      assert function_exported?(Stripe.Checkout.Session, :retrieve, 1)
      assert function_exported?(Stripe.Terminal.ConnectionToken, :create, 1)
    end

    test "Webhook, Converter, Config, and Error APIs we use still exist" do
      assert function_exported?(Stripe.Webhook, :construct_event, 3)
      assert function_exported?(Stripe.Webhook, :construct_event, 4)
      assert function_exported?(Stripe.Converter, :convert_result, 1)
      assert function_exported?(Stripe.Config, :resolve, 1)
      assert function_exported?(Stripe.Config, :resolve, 2)
      assert function_exported?(Stripe.WebhookPlug, :init, 1)
      assert function_exported?(Stripe.WebhookPlug, :call, 2)

      callbacks = Stripe.WebhookHandler.behaviour_info(:callbacks)
      assert {:handle_event, 1} in callbacks
    end
  end

  describe "3.3.3 changelog" do
    test "documents the hackney 4.9 floor and has no breaking changes" do
      changelog = File.read!(@changelog)

      v333 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "[3.3.3]"))

      assert v333
      assert v333 =~ "2026-10-29"
      assert v333 =~ "Require hackney"
      assert v333 =~ "4.9"
      assert v333 =~ "security fixes"
      assert v333 =~ "common-config sync"
      refute v333 =~ "Breaking"
    end
  end

  describe "3.3.3 still dispatches HTTP through http_module" do
    test "API.request still calls http_module().request/5" do
      source = File.read!(@api)
      assert source =~ "Config.resolve(:http_module, :hackney)"

      assert source =~
               "http_module().request(method, url, Map.to_list(headers), body, opts)"
    end

    test "config, runtime, and application still set Ysc.Stripe.HttpClient" do
      assert Stripe.Config.resolve(:http_module, :hackney) == HttpClient
      assert Application.get_env(:stripity_stripe, :http_module) == HttpClient

      assert Application.get_env(:stripity_stripe, :use_connection_pool) ==
               false

      config = File.read!(@config)
      runtime = File.read!(@runtime)
      application = File.read!(@application)
      assert config =~ "http_module: Ysc.Stripe.HttpClient"
      assert runtime =~ "http_module: Ysc.Stripe.HttpClient"
      assert application =~ "http_module, Ysc.Stripe.HttpClient"
      assert application =~ "use_connection_pool, false"
    end

    test "HttpClient still exposes the hackney-compatible request/5" do
      assert function_exported?(HttpClient, :request, 5)
      source = File.read!(@http_client)
      assert source =~ "redirect: false"
      assert source =~ "Req.request"
    end

    test "StripeClient still calls the resource APIs through RetryHelper" do
      assert function_exported?(StripeClient, :create_payment_intent, 2)
      assert function_exported?(StripeClient, :retrieve_payment_intent, 2)
      assert function_exported?(StripeClient, :cancel_payment_intent, 2)
      assert function_exported?(StripeClient, :create_customer, 1)
      assert function_exported?(StripeClient, :update_customer, 2)
      assert function_exported?(StripeClient, :retrieve_invoice, 2)

      source = File.read!(@stripe_client)
      assert source =~ "Stripe.PaymentIntent.create"
      assert source =~ "Stripe.Customer.create"
      assert source =~ "Stripe.PaymentMethod.attach"
      assert source =~ "Stripe.SetupIntent.create"
      assert source =~ "Stripe.Invoice.retrieve"
    end
  end

  describe "3.3.3 webhook plug wiring is unchanged" do
    test "endpoint still mounts WebhookPlug before parsers" do
      source = File.read!(@endpoint)
      plug_at = :binary.match(source, "plug Stripe.WebhookPlug,")
      parsers_at = :binary.match(source, "plug Plug.Parsers,")
      assert plug_at
      assert parsers_at
      {plug_idx, _} = plug_at
      {parsers_idx, _} = parsers_at
      assert plug_idx < parsers_idx
      assert source =~ ~s|at: "/webhooks/stripe"|
      assert source =~ "handler: Ysc.Stripe.WebhookHandler"

      assert source =~
               "secret: {Application, :get_env, [:stripity_stripe, :webhook_secret]}"
    end

    test "WebhookPlug still reads the body then calls handle_event/1" do
      source = File.read!(@webhook_plug)
      assert source =~ "Conn.read_body(conn)"
      assert source =~ "handle_event!(handler, event)"
    end

    test "Ysc.Stripe.WebhookHandler still exports handle_event/1" do
      assert function_exported?(Ysc.Stripe.WebhookHandler, :handle_event, 1)
      assert function_exported?(Ysc.Stripe.WebhookHandler, :handle_event, 2)
    end
  end

  describe "3.3.3 subscription schedule default is unchanged" do
    test "Subscriptions still defaults schedule API to Stripe.SubscriptionSchedule" do
      source = File.read!(@subscriptions)
      assert source =~ "schedule_api \\\\ Stripe.SubscriptionSchedule"
    end
  end

  describe "3.3.3 converter still builds structs we pattern-match" do
    test "convert_result turns a payment_intent object into Stripe.PaymentIntent" do
      result =
        Stripe.Converter.convert_result(%{
          "id" => "pi_upgrade",
          "object" => "payment_intent",
          "amount" => 100,
          "currency" => "usd",
          "status" => "succeeded"
        })

      assert %Stripe.PaymentIntent{
               id: "pi_upgrade",
               amount: 100,
               currency: "usd",
               status: "succeeded"
             } = result
    end
  end
end
