defmodule Ysc.ExPhoneNumberUpgradeTest do
  @moduledoc """
  Guards the ex_phone_number 0.4.11 → 0.4.12 upgrade.

  0.4.12 is a patch with no public API changes. It:

  * Updates bundled libphonenumber metadata from v9.0.26 to v9.0.41
  * Gates debug logging behind `config :ex_phone_number, :debug_log`
    (default off)
  * Drops Elixir < 1.15 (we are 1.20)

  Hex does not ship CHANGELOG.md. README documents metadata v9.0.41.
  Public `parse/2`, `format/2`, `is_valid_number?/1`,
  `is_possible_number?/1`, and `get_number_type/1` are unchanged.
  LivePhone still uses `Metadata.get_for_region_code/1`,
  `Metadata.get_region_code_for_number/1`,
  `Model.PhoneNumber.get_national_significant_number/1`, and
  `Formatting.format_nsn/3`. extras: none (sweet_xml 0.7.5).
  """
  use ExUnit.Case, async: true

  alias LivePhone.Util
  alias Ysc.Extensions.PhoneNumber

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @config_exs Path.expand("../../config/config.exs", __DIR__)
  @runtime_exs Path.expand("../../config/runtime.exs", __DIR__)
  @readme Path.expand("../../deps/ex_phone_number/README.md", __DIR__)
  @package_mix Path.expand("../../deps/ex_phone_number/mix.exs", __DIR__)
  @phone_metadata Path.expand(
                    "../../deps/ex_phone_number/lib/ex_phone_number/metadata/phone_metadata.ex",
                    __DIR__
                  )
  @metadata Path.expand(
              "../../deps/ex_phone_number/lib/ex_phone_number/metadata.ex",
              __DIR__
            )
  @formatting Path.expand(
                "../../deps/ex_phone_number/lib/ex_phone_number/formatting.ex",
                __DIR__
              )
  @model Path.expand(
           "../../deps/ex_phone_number/lib/ex_phone_number/model/phone_number.ex",
           __DIR__
         )
  @wrapper Path.expand("../../lib/ysc/extensions/phone_number.ex", __DIR__)
  @accounts Path.expand("../../lib/ysc/accounts.ex", __DIR__)
  @live_phone Path.expand("../../lib/ysc_web/components/live_phone.ex", __DIR__)
  @live_phone_util Path.expand(
                     "../../lib/ysc_web/components/live_phone/util.ex",
                     __DIR__
                   )
  @live_phone_country Path.expand(
                        "../../lib/ysc_web/components/live_phone/country.ex",
                        __DIR__
                      )

  setup_all do
    {:ok, _} = Application.ensure_all_started(:ex_phone_number)
    {:module, ExPhoneNumber} = Code.ensure_loaded(ExPhoneNumber)

    {:module, ExPhoneNumber.Metadata} =
      Code.ensure_loaded(ExPhoneNumber.Metadata)

    {:module, ExPhoneNumber.Formatting} =
      Code.ensure_loaded(ExPhoneNumber.Formatting)

    {:module, ExPhoneNumber.Model.PhoneNumber} =
      Code.ensure_loaded(ExPhoneNumber.Model.PhoneNumber)

    {:module, ExPhoneNumber.Metadata.PhoneNumberDescription} =
      Code.ensure_loaded(ExPhoneNumber.Metadata.PhoneNumberDescription)

    {:module, PhoneNumber} = Code.ensure_loaded(PhoneNumber)
    {:module, Util} = Code.ensure_loaded(Util)
    :ok
  end

  describe "0.4.12 Hex lock and public APIs" do
    test "locks the Hex package to 0.4.12" do
      assert to_string(Application.spec(:ex_phone_number, :vsn)) == "0.4.12"
    end

    test "mix.exs pins the 0.4.12 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|{:ex_phone_number, "~> 0.4.12"}|
      refute mix_exs =~ ~s|{:ex_phone_number, "~> 0.4"}|
    end

    test "companion lock is 0.4.12 and extras stay put" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"ex_phone_number": {:hex, :ex_phone_number, "0.4.12"|
      refute lock =~ ~s|"ex_phone_number": {:hex, :ex_phone_number, "0.4.11"|
      assert lock =~ ~s|"sweet_xml": {:hex, :sweet_xml, "0.7.5"|
      assert lock =~ ~s|"telemetry": {:hex, :telemetry, "1.4.2"|
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.0.4"|
    end

    test "parse, format, and validation APIs we use still exist" do
      assert function_exported?(ExPhoneNumber, :parse, 2)
      assert function_exported?(ExPhoneNumber, :format, 2)
      assert function_exported?(ExPhoneNumber, :is_valid_number?, 1)
      assert function_exported?(ExPhoneNumber, :is_possible_number?, 1)
      assert function_exported?(ExPhoneNumber, :is_possible_number?, 2)
      assert function_exported?(ExPhoneNumber, :get_number_type, 1)
    end

    test "Metadata and Formatting APIs LivePhone uses still exist" do
      assert function_exported?(ExPhoneNumber.Metadata, :get_for_region_code, 1)

      assert function_exported?(
               ExPhoneNumber.Metadata,
               :get_region_code_for_number,
               1
             )

      assert function_exported?(
               ExPhoneNumber.Model.PhoneNumber,
               :get_national_significant_number,
               1
             )

      assert function_exported?(ExPhoneNumber.Formatting, :format_nsn, 3)
      assert function_exported?(ExPhoneNumber.Formatting, :format_nsn, 4)
    end

    test "package elixir requirement is still 1.15 which we satisfy" do
      mix_exs = File.read!(@package_mix)
      assert mix_exs =~ ~s(elixir: "~> 1.15")
      assert Version.match?(System.version(), "~> 1.15")
    end
  end

  describe "0.4.12 docs and source" do
    test "README documents libphonenumber metadata v9.0.41" do
      readme = File.read!(@readme)
      assert readme =~ "Current metadata version: v9.0.41."
      refute readme =~ "v9.0.26"
    end

    test "debug logging is opt-in via Application env, default off" do
      source = File.read!(@phone_metadata)
      assert source =~ "defp log_debug(message_or_func, metadata \\\\ []) do"
      assert source =~ "if Application.get_env(:ex_phone_number, :debug_log) do"
      assert source =~ "Logger.debug(message_or_func, metadata)"
      refute Application.get_env(:ex_phone_number, :debug_log)
    end

    test "app config does not enable debug_log or a custom metadata file" do
      config = File.read!(@config_exs)
      runtime = File.read!(@runtime_exs)
      refute config =~ "config :ex_phone_number"
      refute runtime =~ "config :ex_phone_number"
      refute config =~ ":debug_log"
      refute runtime =~ ":metadata_file"
    end

    test "Metadata still compiles from the bundled XML" do
      source = File.read!(@metadata)
      assert source =~ ~s|Path.join("resources", "PhoneNumberMetadata.xml")|

      assert source =~
               "Application.compile_env(:ex_phone_number, :metadata_file"

      refute source =~ "Tesla"
    end

    test "format_nsn and national significant number still match LivePhone usage" do
      formatting = File.read!(@formatting)
      model = File.read!(@model)

      assert formatting =~
               "def format_nsn(number, %PhoneMetadata{} = metadata, number_format, carrier_code \\\\ nil)"

      assert model =~
               "def get_national_significant_number(phone_number = %PhoneNumber{})"
    end
  end

  describe "0.4.12 metadata still covers our regions and formats" do
    test "parses, validates, and formats a US number" do
      assert {:ok, parsed} = ExPhoneNumber.parse("+14155551234", "US")
      assert ExPhoneNumber.is_valid_number?(parsed)
      assert ExPhoneNumber.is_possible_number?(parsed)
      assert ExPhoneNumber.format(parsed, :e164) == "+14155551234"
      assert ExPhoneNumber.format(parsed, :national) == "(415) 555-1234"
      assert ExPhoneNumber.Metadata.get_region_code_for_number(parsed) == "US"
    end

    test "parses a Canadian number as CA for SMS support" do
      assert {:ok, parsed} = ExPhoneNumber.parse("+16135551234", "CA")
      assert ExPhoneNumber.is_valid_number?(parsed)
      assert ExPhoneNumber.Metadata.get_region_code_for_number(parsed) == "CA"
    end

    test "parses a Swedish number outside SMS-supported regions" do
      assert {:ok, parsed} = ExPhoneNumber.parse("+46701234567", "SE")
      assert ExPhoneNumber.is_valid_number?(parsed)
      assert ExPhoneNumber.Metadata.get_region_code_for_number(parsed) == "SE"
    end

    test "Ysc wrapper still displays US numbers nationally and gates SMS" do
      assert PhoneNumber.format_for_display("+14155551234") == "(415) 555-1234"
      assert PhoneNumber.sms_supported?("+14155551234")
      assert PhoneNumber.sms_supported?("+16135551234")
      refute PhoneNumber.sms_supported?("+46701234567")
    end

    test "LivePhone.Util still validates and normalizes US numbers" do
      assert Util.valid?("+16502530000")
      assert Util.normalize("+1 (650) 253-0000", "US") == {:ok, "+16502530000"}

      assert {:ok, %LivePhone.Country{code: "US", region_code: "1"}} =
               Util.get_country("+16502530000")
    end

    test "US metadata still has example numbers for LivePhone masks" do
      metadata = ExPhoneNumber.Metadata.get_for_region_code("US")
      assert metadata.country_code == 1
      assert is_binary(metadata.fixed_line.example_number)
      assert metadata.fixed_line.example_number != ""

      assert %ExPhoneNumber.Metadata.PhoneNumberDescription{} =
               metadata.fixed_line
    end
  end

  describe "app still uses the same ExPhoneNumber entry points" do
    test "wrapper, accounts, and LivePhone keep the 0.4.11 call sites" do
      wrapper = File.read!(@wrapper)
      accounts = File.read!(@accounts)
      live_phone = File.read!(@live_phone)
      util = File.read!(@live_phone_util)
      country = File.read!(@live_phone_country)

      assert wrapper =~ "ExPhoneNumber.parse(phone_number, opts)"
      assert wrapper =~ "ExPhoneNumber.is_valid_number?(phone_number)"
      assert wrapper =~ "ExPhoneNumber.format(parsed, :national)"

      assert wrapper =~
               "ExPhoneNumber.Metadata.get_region_code_for_number(parsed)"

      assert accounts =~ "ExPhoneNumber.parse(cleaned, country_code)"
      assert accounts =~ "ExPhoneNumber.format(parsed, :e164)"
      assert live_phone =~ "ExPhoneNumber.Metadata.get_for_region_code"
      assert live_phone =~ "ExPhoneNumber.Formatting.format_nsn"
      assert live_phone =~ "get_national_significant_number"

      assert live_phone =~
               "%ExPhoneNumber.Metadata.PhoneNumberDescription{}"

      assert util =~ "ExPhoneNumber.parse(phone, nil)"
      assert util =~ "ExPhoneNumber.is_valid_number?(parsed_phone)"
      assert country =~ "Metadata.get_for_region_code(country_code)"
      assert country =~ "ExPhoneNumber.Metadata.get_region_code_for_number()"
    end
  end
end
