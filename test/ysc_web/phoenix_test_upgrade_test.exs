defmodule YscWeb.PhoenixTestUpgradeTest do
  @moduledoc """
  Guards the phoenix_test 0.12.1 → 0.14.0 upgrade.

  0.13.0 adds regex `assert_path` / `refute_path`, sends `_unused_*` on
  LiveView `phx-change` for untouched fields, and submits only the
  activated submitter. 0.13.1 drops the Elixir floor back to 1.18
  (we are 1.20). 0.14.0 makes LiveView assertion retry interval
  configurable (`:timeout_interval_wait_time`, default 100 ms), raises
  on unsupported assertion options, refuses `fill_in` on readonly
  fields, keeps typed values through `phx-trigger-action` submits, and
  honors `phx-no-unused-field` on change payloads.

  We only set `:endpoint` in `config/test.exs`. We do not import
  PhoenixTest in ConnCase or configure `:timeout_interval_wait_time`.
  Registration and security LiveViews use `phx-trigger-action`; we
  still drive those with LiveViewTest. We do not use
  `phx-no-unused-field`. `mix deps.update` also pulled ranch 2.4.0,
  phoenix_template 1.1.0, and websock_adapter 0.7.2; phoenix_template
  and websock_adapter stay 1.0.4 / 0.6.0. Ranch is independently
  pinned at 2.4.0.
  """
  use YscWeb.ConnCase, async: true

  import PhoenixTest

  alias PhoenixTest.Assertions
  alias PhoenixTest.Element.Field
  alias PhoenixTest.Element.Form
  alias PhoenixTest.LiveViewTimeout

  @mix_exs Path.expand("../../mix.exs", __DIR__)
  @mix_lock Path.expand("../../mix.lock", __DIR__)
  @test_exs Path.expand("../../config/test.exs", __DIR__)
  @conn_case Path.expand("../../test/support/conn_case.ex", __DIR__)
  @changelog Path.expand("../../deps/phoenix_test/CHANGELOG.md", __DIR__)
  @package_mix Path.expand("../../deps/phoenix_test/mix.exs", __DIR__)
  @phoenix_test_ex Path.expand(
                     "../../deps/phoenix_test/lib/phoenix_test.ex",
                     __DIR__
                   )
  @assertions_ex Path.expand(
                   "../../deps/phoenix_test/lib/phoenix_test/assertions.ex",
                   __DIR__
                 )
  @field_ex Path.expand(
              "../../deps/phoenix_test/lib/phoenix_test/element/field.ex",
              __DIR__
            )
  @form_ex Path.expand(
             "../../deps/phoenix_test/lib/phoenix_test/element/form.ex",
             __DIR__
           )
  @live_ex Path.expand(
             "../../deps/phoenix_test/lib/phoenix_test/live.ex",
             __DIR__
           )
  @timeout_ex Path.expand(
                "../../deps/phoenix_test/lib/phoenix_test/live_view_timeout.ex",
                __DIR__
              )
  @registration_live Path.expand(
                       "../../lib/ysc_web/live/user_registration_live.ex",
                       __DIR__
                     )
  @security_live Path.expand(
                   "../../lib/ysc_web/live/user_security_live.ex",
                   __DIR__
                 )

  setup_all do
    {:module, PhoenixTest} = Code.ensure_loaded(PhoenixTest)
    {:module, Assertions} = Code.ensure_loaded(Assertions)
    {:module, Field} = Code.ensure_loaded(Field)
    {:module, Form} = Code.ensure_loaded(Form)
    {:module, LiveViewTimeout} = Code.ensure_loaded(LiveViewTimeout)
    :ok
  end

  describe "0.14.0 Hex lock and public APIs" do
    test "locks the Hex package to 0.14.0" do
      assert to_string(Application.spec(:phoenix_test, :vsn)) == "0.14.0"
    end

    test "mix.exs pins the 0.14.0 floor" do
      mix_exs = File.read!(@mix_exs)

      assert mix_exs =~
               ~s({:phoenix_test, "~> 0.14.0", only: :test, runtime: false})
    end

    test "companion extras stay on ranch 2.4.0, phoenix_template 1.0.4, websock_adapter 0.6.0" do
      lock = File.read!(@mix_lock)
      assert lock =~ ~s|"phoenix_test": {:hex, :phoenix_test, "0.14.0"|
      refute lock =~ ~s|"phoenix_test": {:hex, :phoenix_test, "0.12.1"|
      assert lock =~ ~s|"ranch": {:hex, :ranch, "2.4.0"|
      refute lock =~ ~s|"ranch": {:hex, :ranch, "2.3.0"|
      assert lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.0.4"|
      refute lock =~ ~s|"phoenix_template": {:hex, :phoenix_template, "1.1.0"|
      assert lock =~ ~s|"websock_adapter": {:hex, :websock_adapter, "0.6.0"|
      refute lock =~ ~s|"websock_adapter": {:hex, :websock_adapter, "0.7.2"|
    end

    test "visit, fill_in, assert_has, and path helpers still exist" do
      assert {:module, _} = Code.ensure_loaded(PhoenixTest)
      assert function_exported?(PhoenixTest, :visit, 2)
      assert function_exported?(PhoenixTest, :fill_in, 3)
      assert function_exported?(PhoenixTest, :fill_in, 4)
      assert function_exported?(PhoenixTest, :click_link, 2)
      assert function_exported?(PhoenixTest, :click_button, 2)
      assert function_exported?(PhoenixTest, :submit, 1)
      assert function_exported?(PhoenixTest, :assert_has, 2)
      assert function_exported?(PhoenixTest, :assert_has, 3)
      assert function_exported?(PhoenixTest, :refute_has, 2)
      assert function_exported?(PhoenixTest, :refute_has, 3)
      assert function_exported?(PhoenixTest, :assert_path, 2)
      assert function_exported?(PhoenixTest, :assert_path, 3)
      assert function_exported?(PhoenixTest, :refute_path, 2)
      assert function_exported?(PhoenixTest, :refute_path, 3)
    end

    test "package elixir requirement is 1.18 which we satisfy" do
      mix_exs = File.read!(@package_mix)
      assert mix_exs =~ ~s(elixir: "~> 1.18")
      assert Version.match?(System.version(), "~> 1.18")
    end

    test "changelog records 0.13.0, 0.13.1, and 0.14.0" do
      changelog = File.read!(@changelog)
      assert changelog =~ "## 0.14.0 - 2026-10-30"
      assert changelog =~ "## 0.13.1 - 2026-10-23"
      assert changelog =~ "## 0.13.0 - 2026-10-23"
      assert changelog =~ "Make LiveView timeout intervals configurable"
      assert changelog =~ "Reject unsupported assertion options"
      assert changelog =~ "Do not allow filling readonly form fields"

      assert changelog =~
               "Preserve typed values through LiveView trigger-action submits"

      assert changelog =~ "Support regular expressions in `assert_path/2`"
    end
  end

  describe "app usage is still compile-time endpoint only" do
    test "config/test.exs sets the endpoint and does not set a retry interval" do
      test_exs = File.read!(@test_exs)
      assert test_exs =~ "config :phoenix_test, :endpoint, YscWeb.Endpoint"
      refute test_exs =~ "timeout_interval_wait_time"
      assert Application.get_env(:phoenix_test, :endpoint) == YscWeb.Endpoint

      assert Application.get_env(:phoenix_test, :timeout_interval_wait_time) ==
               nil
    end

    test "ConnCase does not import PhoenixTest" do
      refute File.read!(@conn_case) =~ "import PhoenixTest"
    end

    test "app templates do not use phx-no-unused-field" do
      for path <- Path.wildcard("lib/**/*.{ex,heex}") do
        refute File.read!(path) =~ "phx-no-unused-field"
      end
    end

    test "registration and security LiveViews still use phx-trigger-action" do
      registration = File.read!(@registration_live)
      security = File.read!(@security_live)
      assert registration =~ ~s(phx-trigger-action={@trigger_submit})
      assert registration =~ ~s(id="registration_form")
      assert security =~ ~s(phx-trigger-action={@trigger_submit})
      assert security =~ ~s(id="password_form")
    end
  end

  describe "0.14.0 LiveView timeout interval" do
    test "defaults to 100 ms when unset" do
      timeout_src = File.read!(@timeout_ex)
      phoenix_test_src = File.read!(@phoenix_test_ex)

      assert timeout_src =~
               "Application.get_env(:phoenix_test, :timeout_interval_wait_time, 100)"

      assert phoenix_test_src =~
               "config :phoenix_test, :timeout_interval_wait_time, 20"

      assert LiveViewTimeout.interval_wait_time() == 100
    end

    test "accepts a positive integer override and rejects non-positive values" do
      previous = Application.get_env(:phoenix_test, :timeout_interval_wait_time)

      on_exit(fn ->
        if previous do
          Application.put_env(
            :phoenix_test,
            :timeout_interval_wait_time,
            previous
          )
        else
          Application.delete_env(:phoenix_test, :timeout_interval_wait_time)
        end
      end)

      Application.put_env(:phoenix_test, :timeout_interval_wait_time, 20)
      assert LiveViewTimeout.interval_wait_time() == 20

      Application.put_env(:phoenix_test, :timeout_interval_wait_time, 0)

      assert_raise ArgumentError, ~r/must be a positive integer/, fn ->
        LiveViewTimeout.interval_wait_time()
      end

      Application.put_env(:phoenix_test, :timeout_interval_wait_time, :fast)

      assert_raise ArgumentError, ~r/must be a positive integer/, fn ->
        LiveViewTimeout.interval_wait_time()
      end
    end
  end

  describe "0.14.0 reject unsupported assertion options" do
    test "known assert_has options still parse" do
      opts =
        Assertions.Opts.parse(
          text: "Privacy Policy",
          exact: true,
          count: 1,
          timeout: 100
        )

      assert opts.text == "Privacy Policy"
      assert opts.exact == true
      assert opts.count == 1
    end

    test "unknown assertion options raise ArgumentError" do
      assertions = File.read!(@assertions_ex)

      assert assertions =~
               "Keyword.validate!(opts, [:at, :checked, :count, :exact, :label, :selected, :text, :value, :timeout])"

      assert_raise ArgumentError, ~r/unknown keys \[:foo\]/, fn ->
        Assertions.Opts.parse(text: "x", foo: 1)
      end
    end
  end

  describe "0.14.0 readonly fill_in" do
    test "validate_fillable! raises on a readonly text input and allows a writable one" do
      field_src = File.read!(@field_ex)
      live_src = File.read!(@live_ex)
      assert field_src =~ "Cannot fill in"
      assert field_src =~ "because it is readonly."
      assert live_src =~ "Field.validate_fillable!()"

      readonly =
        Field.find_input!(
          ~s(<form><label for="code">Code</label><input id="code" name="code" type="text" readonly></form>),
          ["input:not([type='hidden'])", "textarea"],
          "Code",
          []
        )

      assert_raise ArgumentError,
                   ~r/Cannot fill in "Code" because it is readonly/,
                   fn ->
                     Field.validate_fillable!(readonly)
                   end

      writable =
        Field.find_input!(
          ~s(<form><label for="name">Name</label><input id="name" name="name" type="text"></form>),
          ["input:not([type='hidden'])", "textarea"],
          "Name",
          []
        )

      assert %Field{} = Field.validate_fillable!(writable)
    end
  end

  describe "0.13.0 unused-field and trigger-action sources" do
    test "LiveView phx-change still prefixes untouched fields with _unused_" do
      live_src = File.read!(@live_ex)
      form_src = File.read!(@form_ex)
      assert live_src =~ ~s("_unused_" <> field)
      assert live_src =~ "phx-trigger-action"

      assert live_src =~
               "FormData.override(form.form_data, if(active_form?, do: active_form.form_data, else: FormData.new()))"

      assert form_src =~ "phx-no-unused-field"
      assert function_exported?(Form, :phx_no_unused_field?, 1)
      assert function_exported?(Form, :changeable_field_names, 1)
    end

    test "phx-no-unused-field on the form skips unused-field names" do
      html =
        ~s(<form phx-no-unused-field><label for="n">Name</label><input id="n" name="name" type="text"></form>)

      form = Form.find!(html, "form")
      assert Form.phx_no_unused_field?(form)
      assert Form.changeable_field_names(form) == []
    end

    test "per-input phx-no-unused-field is omitted from changeable names" do
      html =
        ~s(<form><label for="n">Name</label><input id="n" name="name" type="text"><label for="e">Email</label><input id="e" name="email" type="email" phx-no-unused-field></form>)

      form = Form.find!(html, "form")
      refute Form.phx_no_unused_field?(form)
      assert Form.changeable_field_names(form) == ["name"]
    end
  end

  describe "0.13/0.14 session helpers on static and LiveView pages" do
    test "static privacy policy supports regex assert_path and rejects unknown assertion opts",
         %{conn: conn} do
      session =
        conn
        |> visit(~p"/privacy-policy")
        |> assert_has("h1", text: "Privacy Policy")
        |> assert_path("/privacy-policy")
        |> assert_path(~r"^/privacy-policy$")
        |> refute_path(~r"^/terms")

      assert_raise ArgumentError, ~r/unknown keys \[:foo\]/, fn ->
        assert_has(session, "h1", text: "Privacy Policy", foo: true)
      end
    end

    test "LiveView home page visit, path regex, fill_in, and timeout option still work",
         %{conn: conn} do
      conn
      |> visit(~p"/")
      |> assert_has("h1", text: "Young Scandinavians Club", timeout: 100)
      |> assert_path(~r"^/$")
      |> fill_in("Email address for newsletter signup",
        with: "guest@example.com"
      )
      |> assert_has("#newsletter-email")
    end
  end
end
