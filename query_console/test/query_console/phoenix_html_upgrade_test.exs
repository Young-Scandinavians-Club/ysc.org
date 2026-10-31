defmodule QueryConsole.PhoenixHtmlUpgradeTest do
  @moduledoc """
  Guards the phoenix_html 4.3.0 → 4.4.0 upgrade.

  4.4.0 is a minor with no documented breaking changes. It patches
  EEF-CVE-2026-117645 (MEDIUM / CVE-2026-117645): `attributes_escape/1`
  rejects binary attribute names that contain whitespace, quotes, `>`,
  `/`, `=`, control characters, or DEL, so a key such as
  `"x onmouseover"` cannot inject an extra attribute. Atom keys remain
  dasherized without that check. It also adds `json_escape/1` for
  embedding encoded JSON in a `<script>` tag.

  Query Console imports `Phoenix.HTML` and uses `Phoenix.HTML.FormField`,
  `Form.normalize_value/2`, and `Form.options_for_select/2`. HEEx
  `{@rest}` spreads LiveView global attrs with compile-time names. We
  do not pass user-controlled attribute names to `attributes_escape/1`
  or call `json_escape/1`. Public form APIs are unchanged.
  """
  use ExUnit.Case, async: true

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @changelog Path.expand("../../deps/phoenix_html/CHANGELOG.md", __DIR__)
  @html_src Path.expand("../../deps/phoenix_html/lib/phoenix_html.ex", __DIR__)
  @web_ex Path.expand("../../lib/query_console_web.ex", __DIR__)
  @core_components Path.expand(
                     "../../lib/query_console_web/components/core_components.ex",
                     __DIR__
                   )

  setup_all do
    {:ok, _} = Application.ensure_all_started(:phoenix_html)
    {:module, Phoenix.HTML} = Code.ensure_loaded(Phoenix.HTML)
    {:module, Phoenix.HTML.Form} = Code.ensure_loaded(Phoenix.HTML.Form)
    {:module, Phoenix.HTML.FormField} = Code.ensure_loaded(Phoenix.HTML.FormField)
    {:module, Phoenix.HTML.Engine} = Code.ensure_loaded(Phoenix.HTML.Engine)
    :ok
  end

  describe "4.4.0 Hex lock and public APIs" do
    test "locks the Hex package to 4.4.0" do
      assert to_string(Application.spec(:phoenix_html, :vsn)) == "4.4.0"
    end

    test "mix.exs pins the patched floor" do
      mix_exs = File.read!(@mix_exs)
      assert mix_exs =~ ~s({:phoenix_html, "~> 4.4.0"})
      refute mix_exs =~ ~s({:phoenix_html, "~> 4.1"})
    end

    test "companion locks stay phoenix_template 1.1.0 and lotus_web 1.4.0" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"phoenix_html": {:hex, :phoenix_html, "4.4.0"|
      refute lock =~ ~s|"phoenix_html": {:hex, :phoenix_html, "4.3.0"|
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.1.0"|
      assert lock =~ ~s|"phoenix_live_view": {:hex, :phoenix_live_view, "1.2.13"|
      assert lock =~ ~s|"lotus_web": {:hex, :lotus_web, "1.4.0"|
    end

    test "HTML and Form APIs Query Console uses still exist" do
      {:module, Phoenix.HTML} = Code.ensure_loaded(Phoenix.HTML)
      {:module, Phoenix.HTML.Form} = Code.ensure_loaded(Phoenix.HTML.Form)
      {:module, Phoenix.HTML.FormField} = Code.ensure_loaded(Phoenix.HTML.FormField)

      assert function_exported?(Phoenix.HTML, :html_escape, 1)
      assert function_exported?(Phoenix.HTML, :raw, 1)
      assert function_exported?(Phoenix.HTML, :safe_to_string, 1)
      assert function_exported?(Phoenix.HTML, :attributes_escape, 1)
      assert function_exported?(Phoenix.HTML, :javascript_escape, 1)
      assert function_exported?(Phoenix.HTML.Form, :normalize_value, 2)
      assert function_exported?(Phoenix.HTML.Form, :options_for_select, 2)
    end

    test "json_escape/1 exists but stays unused in app code" do
      {:module, Phoenix.HTML} = Code.ensure_loaded(Phoenix.HTML)
      assert function_exported?(Phoenix.HTML, :json_escape, 1)

      lib_files =
        Path.wildcard(Path.expand("../../lib/**/*.{ex,heex}", __DIR__))

      refute Enum.any?(lib_files, fn path ->
               File.read!(path) =~ "json_escape"
             end)
    end
  end

  describe "4.4.0 changelog" do
    test "documents CVE-2026-117645 and json_escape/1" do
      changelog = File.read!(@changelog)

      v440 =
        changelog
        |> String.split("\n## ")
        |> Enum.find(&String.starts_with?(&1, "4.4.0"))

      assert v440
      refute v440 =~ "Breaking"
      assert v440 =~ "CVE-2026-117645"
      assert v440 =~ "attribute names"
      assert v440 =~ "json_escape/1"
    end
  end

  describe "EEF-CVE-2026-117645 binary attribute names" do
    test "source validates binary keys against whitespace and quotes" do
      source = File.read!(@html_src)
      assert source =~ "validate_attr_name!"
      assert source =~ ~S|@invalid_attr_chars ~c"\"'>/= "|
    end

    test "space in a binary name raises instead of injecting an attribute" do
      assert_raise ArgumentError, ~r/attribute name/, fn ->
        Phoenix.HTML.attributes_escape(%{"x onmouseover" => "alert(1)"})
      end
    end

    test "quote in a binary name raises" do
      assert_raise ArgumentError, ~r/attribute name/, fn ->
        Phoenix.HTML.attributes_escape(%{~s|x" onclick| => "y"})
      end
    end

    test "nested data binary names are validated too" do
      assert_raise ArgumentError, ~r/attribute name/, fn ->
        Phoenix.HTML.attributes_escape(%{"data" => [{"x onmouseover", "alert(1)"}]})
      end
    end

    test "valid atom and binary attributes still render" do
      html =
        [title: "the title", id: "the id", selected: true]
        |> Phoenix.HTML.attributes_escape()
        |> Phoenix.HTML.safe_to_string()

      assert html == ~s| title="the title" id="the id" selected|

      html =
        %{"data-confirm" => "Are you sure?", "aria-label" => "Save"}
        |> Phoenix.HTML.attributes_escape()
        |> Phoenix.HTML.safe_to_string()

      assert html =~ ~s|data-confirm="Are you sure?"|
      assert html =~ ~s|aria-label="Save"|
    end

    test "atom keys still dasherize without the binary-name check" do
      html =
        [phx_click: "save"]
        |> Phoenix.HTML.attributes_escape()
        |> Phoenix.HTML.safe_to_string()

      assert html == ~s| phx-click="save"|
    end
  end

  describe "Form APIs used by CoreComponents" do
    test "normalize_value/2 still handles checkbox and textarea" do
      {:module, Phoenix.HTML.Form} = Code.ensure_loaded(Phoenix.HTML.Form)
      assert Phoenix.HTML.Form.normalize_value("checkbox", "true") == true
      assert Phoenix.HTML.Form.normalize_value("text", "hello") == "hello"

      # textarea still prefixes a newline so the first line is not eaten
      assert {:safe, iodata} =
               Phoenix.HTML.Form.normalize_value("textarea", "hello")

      assert IO.iodata_to_binary(iodata) == "\nhello"
    end

    test "options_for_select/2 still marks the selected option" do
      {:module, Phoenix.HTML.Form} = Code.ensure_loaded(Phoenix.HTML.Form)

      html =
        ["alpha", "beta"]
        |> Phoenix.HTML.Form.options_for_select("alpha")
        |> Phoenix.HTML.safe_to_string()

      assert html =~ ~s|value="alpha"|
      assert html =~ "selected"
      assert html =~ ~s|value="beta"|
    end
  end

  describe "Query Console usage stays on compile-time attribute names" do
    test "html helpers still import Phoenix.HTML" do
      web = File.read!(@web_ex)
      assert web =~ "import Phoenix.HTML"
    end

    test "core components still use FormField, normalize_value, and rest attrs" do
      core = File.read!(@core_components)
      assert core =~ "Phoenix.HTML.FormField"
      assert core =~ "Phoenix.HTML.Form.normalize_value"
      assert core =~ "Phoenix.HTML.Form.options_for_select"
      assert core =~ "{@rest}"
      refute core =~ "attributes_escape"
    end

    test "app code does not call attributes_escape" do
      lib_files =
        Path.wildcard(Path.expand("../../lib/**/*.{ex,heex}", __DIR__))

      refute Enum.any?(lib_files, fn path ->
               File.read!(path) =~ "attributes_escape"
             end)
    end
  end
end
