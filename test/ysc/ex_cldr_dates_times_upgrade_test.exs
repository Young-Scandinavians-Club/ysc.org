defmodule Ysc.ExCldrDatesTimesUpgradeTest do
  @moduledoc """
  Guards the ex_cldr_dates_times 2.25.6 → 2.25.8 upgrade.

  2.25.7/2.25.8 are patches with no public API changes. They:

  * Drop the deprecated mix.exs `xref: [exclude: [:eprof]]` that warned
    on Elixir 1.20 when compiling as a dependency (2.25.7)
  * Return `%{}` from `meta_zones/1` for locales without metazone names
    (`:und`) so `z`/`zzzz`/`v`/`vvvv` and
    `Cldr.DateTime.Timezone.non_location_format/2` do not raise
    `BadMapError` (2.25.8)

  Public `Cldr.DateTime.to_string/3`, `Cldr.Date.to_string/3`, and
  `Cldr.Time.to_string/3` are unchanged. We configure `Cldr.DateTime`
  as a `Ysc.Cldr` provider (generated Format/Formatter modules) and
  format dates with `Calendar.strftime/2`, not Cldr timezone names.
  extras: none (ex_cldr_numbers 2.38.3 / cldr_utils 2.29.7 /
  telemetry 1.4.2 / phoenix_template 1.0.4).
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand(
               "../../deps/ex_cldr_dates_times/CHANGELOG.md",
               __DIR__
             )
  @package_mix Path.expand(
                 "../../deps/ex_cldr_dates_times/mix.exs",
                 __DIR__
               )
  @format_backend Path.expand(
                    "../../deps/ex_cldr_dates_times/lib/cldr/backend/format.ex",
                    __DIR__
                  )
  @cldr Path.expand("../../lib/ysc/cldr.ex", __DIR__)
  @date_display Path.expand("../../lib/ysc_web/date_display.ex", __DIR__)
  @config_exs Path.expand("../../config/config.exs", __DIR__)

  setup_all do
    {:ok, _} = Application.ensure_all_started(:ex_cldr_dates_times)
    {:module, Cldr.DateTime} = Code.ensure_loaded(Cldr.DateTime)
    {:module, Cldr.Date} = Code.ensure_loaded(Cldr.Date)
    {:module, Cldr.Time} = Code.ensure_loaded(Cldr.Time)

    {:module, Cldr.DateTime.Timezone} =
      Code.ensure_loaded(Cldr.DateTime.Timezone)

    {:module, Ysc.Cldr} = Code.ensure_loaded(Ysc.Cldr)

    {:module, Ysc.Cldr.DateTime.Format} =
      Code.ensure_loaded(Ysc.Cldr.DateTime.Format)

    {:module, Ysc.Cldr.DateTime.Formatter} =
      Code.ensure_loaded(Ysc.Cldr.DateTime.Formatter)

    {:module, Ysc.Cldr.DateTime} = Code.ensure_loaded(Ysc.Cldr.DateTime)

    :ok
  end

  describe "2.25.8 Hex lock and public APIs" do
    test "locks the Hex package to 2.25.8" do
      assert to_string(Application.spec(:ex_cldr_dates_times, :vsn)) ==
               "2.25.8"
    end

    test "mix.exs pins the 2.25.8 floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s|{:ex_cldr_dates_times, "~> 2.25.8"}|
      refute mix_exs =~ ~s|{:ex_cldr_dates_times, "~> 2.25"}|
    end

    test "companion lock is 2.25.8 and extras stay put" do
      lock = File.read!(@mix_lock)

      assert lock =~
               ~s|"ex_cldr_dates_times": {:hex, :ex_cldr_dates_times, "2.25.8"|

      refute lock =~
               ~s|"ex_cldr_dates_times": {:hex, :ex_cldr_dates_times, "2.25.6"|

      refute lock =~
               ~s|"ex_cldr_dates_times": {:hex, :ex_cldr_dates_times, "2.25.7"|

      assert lock =~
               ~s|"ex_cldr_numbers": {:hex, :ex_cldr_numbers, "2.38.3"|

      assert lock =~ ~s|"cldr_utils": {:hex, :cldr_utils, "2.29.7"|
      assert lock =~ ~s|"castore": {:hex, :castore, "1.0.21"|
      assert lock =~ ~s|"telemetry": {:hex, :telemetry, "1.4.2"|

      assert lock =~
               ~s|"phoenix_template": {:hex, :phoenix_template, "1.0.4"|
    end

    test "to_string APIs we would call still exist" do
      assert function_exported?(Cldr.DateTime, :to_string, 1)
      assert function_exported?(Cldr.DateTime, :to_string, 2)
      assert function_exported?(Cldr.DateTime, :to_string, 3)
      assert function_exported?(Cldr.DateTime, :to_string!, 1)
      assert function_exported?(Cldr.DateTime, :to_string!, 2)
      assert function_exported?(Cldr.DateTime, :to_string!, 3)
      assert function_exported?(Cldr.Date, :to_string, 1)
      assert function_exported?(Cldr.Date, :to_string, 2)
      assert function_exported?(Cldr.Date, :to_string, 3)
      assert function_exported?(Cldr.Time, :to_string, 1)
      assert function_exported?(Cldr.Time, :to_string, 2)
      assert function_exported?(Cldr.Time, :to_string, 3)
    end

    test "Timezone.non_location_format/2 still exists" do
      assert function_exported?(
               Cldr.DateTime.Timezone,
               :non_location_format,
               1
             )

      assert function_exported?(
               Cldr.DateTime.Timezone,
               :non_location_format,
               2
             )
    end

    test "generated Ysc.Cldr DateTime Format and Formatter still exist" do
      assert function_exported?(Ysc.Cldr.DateTime.Format, :meta_zones, 0)
      assert function_exported?(Ysc.Cldr.DateTime.Format, :meta_zones, 1)
      assert function_exported?(Ysc.Cldr.DateTime, :to_string, 1)
      assert function_exported?(Ysc.Cldr.DateTime, :to_string, 2)
    end

    test "package elixir requirement is still 1.12 which we satisfy" do
      mix_exs = File.read!(@package_mix)
      assert mix_exs =~ ~s(elixir: "~> 1.12")
      refute mix_exs =~ "xref:"
      refute mix_exs =~ ":eprof"
      assert Version.match?(System.version(), "~> 1.12")
    end
  end

  describe "2.25.8 docs and source" do
    test "changelog documents 2.25.7 xref and 2.25.8 und meta_zones" do
      changelog = File.read!(@changelog)
      sections = String.split(changelog, "\n## ")

      latest =
        Enum.find(
          sections,
          &String.starts_with?(&1, "Cldr_Dates_Times v2.25.8")
        )

      previous =
        Enum.find(
          sections,
          &String.starts_with?(&1, "Cldr_Dates_Times v2.25.7")
        )

      assert latest
      assert latest =~ "BadMapError"
      assert latest =~ "meta_zones/1"
      assert latest =~ ":und"
      assert previous
      assert previous =~ "xref"
      assert previous =~ ":eprof"
      assert previous =~ "Elixir 1.20"
    end

    test "format backend defaults missing metazone names to an empty map" do
      source = File.read!(@format_backend)

      assert source =~
               "# The root locale (`und`) has no metazone names. An empty map keeps"

      assert source =~
               "get_in(locale_data, [:dates, :time_zone_names, :metazone]) || %{}"
    end
  end

  describe "2.25.8 still formats our :en locale" do
    test "formats a DateTime and Date in :en" do
      dt = ~U[2024-06-15 20:00:00Z]

      assert {:ok, formatted} =
               Cldr.DateTime.to_string(dt, Ysc.Cldr,
                 locale: :en,
                 format: :medium
               )

      assert is_binary(formatted)
      assert formatted != ""

      assert {:ok, date} =
               Cldr.Date.to_string(~D[2024-06-15], Ysc.Cldr, locale: :en)

      assert date =~ "2024"
    end

    test "en meta_zones is a map so timezone symbols do not raise" do
      assert {:ok, zones} = Ysc.Cldr.DateTime.Format.meta_zones(:en)
      assert is_map(zones)

      dt = ~U[2024-06-15 20:00:00Z]

      assert {:ok, named} =
               Cldr.DateTime.to_string(dt, Ysc.Cldr,
                 locale: :en,
                 format: "yyyy-MM-dd HH:mm z"
               )

      assert named =~ "2024"
      refute named == ""
    end

    test "non_location_format still returns a string for Pacific" do
      assert {:ok, name} =
               Cldr.DateTime.Timezone.non_location_format(
                 "America/Los_Angeles",
                 locale: :en,
                 backend: Ysc.Cldr
               )

      assert is_binary(name)
      assert name != ""
    end

    test "und meta_zones is a map when the root locale is known" do
      if :und in Ysc.Cldr.known_locale_names() do
        assert {:ok, zones} = Ysc.Cldr.DateTime.Format.meta_zones(:und)
        assert is_map(zones)
      else
        assert :en in Ysc.Cldr.known_locale_names()
      end
    end
  end

  describe "app still uses Cldr.DateTime only as a provider" do
    test "Ysc.Cldr keeps DateTime among providers and :en only" do
      cldr = File.read!(@cldr)
      assert cldr =~ "Cldr.DateTime,"
      assert cldr =~ "locales: [:en]"
      assert cldr =~ "default_locale: :en"
      refute cldr =~ "Cldr.DateTime.to_string"
    end

    test "config still points Money and Cldr at Ysc.Cldr" do
      config = File.read!(@config_exs)
      assert config =~ "config :ex_cldr, default_backend: Ysc.Cldr"
      assert config =~ "config :ex_money, default_cldr_backend: Ysc.Cldr"
    end

    test "member-facing dates still use Calendar.strftime not Cldr" do
      date_display = File.read!(@date_display)
      assert date_display =~ "Calendar.strftime"
      refute date_display =~ "Cldr.DateTime"
      refute date_display =~ "Cldr.Date.to_string"
    end
  end
end
