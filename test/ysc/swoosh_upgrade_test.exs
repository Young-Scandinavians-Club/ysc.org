defmodule Ysc.SwooshUpgradeTest do
  @moduledoc """
  Guards the swoosh 1.27.1 → 1.28.1 upgrade.

  1.28.0 adds `Swoosh.Adapters.TurboSMTP`. 1.28.1 adds CC on the
  Customer.io adapter. AmazonSES, `Swoosh.Email`, and `Swoosh.Mailer`
  are byte-identical to 1.27.1. We deliver with AmazonSES in production
  and `Swoosh.Adapters.Test` in tests, so those adapters are unused.
  """
  use ExUnit.Case, async: true

  import Swoosh.TestAssertions

  alias Ysc.Mailer

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @runtime Path.expand("../../config/runtime.exs", __DIR__)
  @amazon_ses Path.expand(
                "../../deps/swoosh/lib/swoosh/adapters/amazon_ses.ex",
                __DIR__
              )
  @customer_io Path.expand(
                 "../../deps/swoosh/lib/swoosh/adapters/customer_io.ex",
                 __DIR__
               )
  @turbo_smtp Path.expand(
                "../../deps/swoosh/lib/swoosh/adapters/turbo_smtp.ex",
                __DIR__
              )

  setup_all do
    {:module, Swoosh.Email} = Code.ensure_loaded(Swoosh.Email)
    {:module, Swoosh.Mailer} = Code.ensure_loaded(Swoosh.Mailer)

    {:module, Swoosh.Adapters.AmazonSES} =
      Code.ensure_loaded(Swoosh.Adapters.AmazonSES)

    :ok
  end

  describe "1.28.1 Hex lock and public APIs" do
    test "locks the Hex package to 1.28.1" do
      assert to_string(Application.spec(:swoosh, :vsn)) == "1.28.1"
    end

    test "mix.exs pins the 1.28.1 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:swoosh, "~> 1.28.1"})
    end

    test "Email, Mailer, and AmazonSES APIs we use still exist" do
      assert function_exported?(Swoosh.Email, :new, 0)
      assert function_exported?(Swoosh.Email, :to, 2)
      assert function_exported?(Swoosh.Email, :from, 2)
      assert function_exported?(Swoosh.Email, :cc, 2)
      assert function_exported?(Swoosh.Email, :subject, 2)
      assert function_exported?(Swoosh.Email, :html_body, 2)
      assert function_exported?(Swoosh.Email, :text_body, 2)
      assert function_exported?(Swoosh.Email, :put_provider_option, 3)
      assert function_exported?(Swoosh.Adapters.AmazonSES, :deliver, 2)
      {:module, Mailer} = Code.ensure_loaded(Mailer)
      # `use Swoosh.Mailer` defines deliver/2 with a default config;
      # `Mailer.deliver(email)` still compiles to that /2 head.
      assert function_exported?(Mailer, :deliver, 2)
    end
  end

  describe "1.28.0 / 1.28.1 unused adapters" do
    test "TurboSMTP adapter is new and not used as our mailer" do
      assert File.exists?(@turbo_smtp)

      {:module, Swoosh.Adapters.TurboSMTP} =
        Code.ensure_loaded(Swoosh.Adapters.TurboSMTP)

      assert function_exported?(Swoosh.Adapters.TurboSMTP, :deliver, 2)

      runtime = File.read!(@runtime)
      refute runtime =~ "Swoosh.Adapters.TurboSMTP"
      refute runtime =~ "Swoosh.Adapters.CustomerIO"

      assert runtime =~ "adapter: Swoosh.Adapters.AmazonSES"
    end

    test "Customer.io prepare_cc is unused; we CC via Swoosh.Email" do
      source = File.read!(@customer_io)
      assert source =~ "|> prepare_cc(email)"
      assert source =~ "defp prepare_cc(body, %Email{cc: []}), do: body"
      assert source =~ "Map.put(body, :cc, render_recipient(cc))"
    end
  end

  describe "AmazonSES SES options we use" do
    test "still maps configuration_set_name and name/value tags" do
      source = File.read!(@amazon_ses)
      assert source =~ "|> prepare_configuration_set_name(email)"
      assert source =~ "|> prepare_tags(email)"

      assert source =~
               "defp prepare_configuration_set_name(body, %{provider_options: %{configuration_set_name: name}}) do"

      assert source =~ ~s[Map.put(body, "ConfigurationSetName", name)]

      assert source =~
               ~S[{"Tags.member.#{index}.Name", name}, {"Tags.member.#{index}.Value", value}]
    end
  end

  describe "Mailer.deliver/1 with Test adapter" do
    test "still delivers to, from, cc, and SES provider options" do
      email =
        Swoosh.Email.new()
        |> Swoosh.Email.to("ada@ysc.org")
        |> Swoosh.Email.from({"YSC", "noreply@ysc.org"})
        |> Swoosh.Email.cc("cc@ysc.org")
        |> Swoosh.Email.subject("Swoosh 1.28.1")
        |> Swoosh.Email.html_body("<p>hello</p>")
        |> Swoosh.Email.text_body("hello")
        |> Swoosh.Email.put_provider_option(
          :configuration_set_name,
          "ysc-tracking"
        )
        |> Swoosh.Email.put_provider_option(:tags, [
          %{name: "env", value: "test"}
        ])

      assert {:ok, _metadata} = Mailer.deliver(email)

      assert_email_sent(fn sent ->
        assert sent.to == [{"", "ada@ysc.org"}]
        assert sent.from == {"YSC", "noreply@ysc.org"}
        assert sent.cc == [{"", "cc@ysc.org"}]
        assert sent.subject == "Swoosh 1.28.1"
        assert sent.html_body == "<p>hello</p>"
        assert sent.text_body == "hello"
        assert sent.provider_options.configuration_set_name == "ysc-tracking"
        assert sent.provider_options.tags == [%{name: "env", value: "test"}]
      end)
    end
  end
end
