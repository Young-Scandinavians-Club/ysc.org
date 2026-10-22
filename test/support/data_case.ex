defmodule Ysc.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Ysc.DataCase, async: true`, although
  this option is not recommended for other databases.

  ## Options

    * `:mox_global_first` — when `true`, enables Mox global mode **before**
      default HTTP/Stripe stubs run so Oban workers and other spawned processes
      can call mocks. Only the process that enables global mode may define stubs
      in shared mode. Resets to private mode when the test exits.

      Pass together with `async: false`, per Mox requirements. Do not use
      `setup :set_mox_global` in the test module: that callback runs *after*
      DataCase stubs, so the next test flakes with
      `only the process that set Mox to global can set expectations/stubs`.

      Example:

          use Ysc.DataCase, async: false, mox_global_first: true

  """

  use ExUnit.CaseTemplate
  import Mox

  using(opts) do
    mox_global_first_flag = Keyword.get(opts, :mox_global_first, false)

    quote do
      use Oban.Testing, repo: Ysc.Repo

      alias Ysc.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Ysc.DataCase
      import Ysc.EmailValidatorTestHelper
      import Ysc.Test.Invoke
      import Mox

      unquote(
        if mox_global_first_flag do
          quote do
            @moduletag :mox_global_first
          end
        else
          quote do
          end
        end
      )
    end
  end

  setup tags do
    Ysc.Test.EnvHelper.reset_environment!()

    if tags[:mox_global_first] do
      Mox.set_mox_global()
      on_exit(fn -> Mox.set_mox_private() end)
    end

    owner = Ysc.DataCase.setup_sandbox(tags)
    # Ensure basic site settings exist, unless the test explicitly opts out.
    # Skip the DB round-trip when settings already exist (e.g. same sandbox process).
    if !tags[:skip_settings_setup] do
      if Ysc.Repo.aggregate(Ysc.SiteSettings.SiteSetting, :count) == 0 do
        Ysc.Settings.ensure_settings_exist()
      end
    end

    invalidate_shared_caches()

    if tags[:process_caches] do
      Application.put_env(:ysc, :process_caches_enabled, true)

      on_exit(fn ->
        Application.put_env(:ysc, :process_caches_enabled, false)
      end)
    end

    stub_default_external_mocks()

    {:ok, sandbox_owner: owner}
  end

  @doc """
  Clears process-global caches that are not tied to the SQL sandbox.

  Cached values from one test's DB snapshot must not leak into another test.
  """
  def invalidate_shared_caches do
    Ysc.PublicContentCache.invalidate()
    Ysc.Events.EventListCache.invalidate()
    Ysc.Bookings.BlackoutListCache.invalidate()
    Ysc.Bookings.AvailabilityCache.invalidate()
    Ysc.Bookings.RoomsListCache.invalidate()
    Ysc.Bookings.SeasonCache.invalidate()
    Ysc.Bookings.PricingRuleCache.invalidate()
    Ysc.Bookings.RefundPolicyCache.invalidate()
    Ysc.Sitemap.invalidate()
    # Settings live in process-global Cachex. SQL sandbox rollback does not
    # undo `all-site-settings`, so a prior test that inserted dummy rows and
    # called `settings/0` can leave Admin Settings rendering `setting1` instead
    # of facebook/instagram. Reload from this test's sandbox.
    Ysc.Settings.warm_cache()
    :ok
  end

  @doc """
  Stubs external service mocks with safe no-op defaults so tests that indirectly
  trigger external calls don't fail with UnexpectedCallError or make real API calls.
  Individual tests can override these stubs with their own expectations.
  """
  def stub_default_external_mocks do
    # Discord HTTP: return ok without making real HTTP calls
    stub(Ysc.Alerts.DiscordHttpMock, :send_webhook, fn _url, _body, _headers ->
      {:ok, :sent}
    end)

    # Stripe PaymentIntent list: leftover no-op for tests that still stub list/1.
    # Hold release now cancels by stored payment_intent_id instead of listing.
    stub(Stripe.PaymentIntentMock, :list, fn _params ->
      {:ok,
       %Stripe.List{
         data: [],
         has_more: false,
         object: "list",
         url: "/v1/payment_intents"
       }}
    end)

    stub_with(Stripe.PaymentMethodMock, Ysc.TestStripePaymentMethodStub)

    # Stripe Customer.create: deterministic test IDs from metadata user_id
    stub(Stripe.CustomerMock, :create, fn params, _opts ->
      user_id =
        case params do
          %{metadata: %{user_id: id}} -> id
          %{"metadata" => %{"user_id" => id}} -> id
          _ -> :erlang.unique_integer([:positive])
        end

      {:ok,
       %Stripe.Customer{
         id: "cus_test_#{user_id}",
         email: Map.get(params, :email) || Map.get(params, "email")
       }}
    end)

    # Stripe Customer.retrieve: e.g. UserSettingsLive verifies customer exists before setup intents
    stub(Stripe.CustomerMock, :retrieve, fn id, _opts ->
      {:ok,
       %Stripe.Customer{
         id: id,
         invoice_settings: %{default_payment_method: nil}
       }}
    end)

    stub(Stripe.CustomerMock, :update, fn id, _params, _opts ->
      {:ok,
       %Stripe.Customer{
         id: id,
         invoice_settings: %{default_payment_method: nil}
       }}
    end)

    stub_with(Stripe.SubscriptionMock, Ysc.TestStripeSubscriptionStub)

    # Stripe Invoice: return empty list and not-found for retrieve/pay
    stub(Stripe.InvoiceMock, :list, fn _params ->
      {:ok,
       %Stripe.List{
         data: [],
         has_more: false,
         object: "list",
         url: "/v1/invoices"
       }}
    end)

    stub(Stripe.InvoiceMock, :retrieve, fn _invoice_id ->
      {:error,
       %Stripe.Error{
         source: :stripe,
         code: :not_found,
         message: "No such invoice",
         request_id: nil,
         extra: %{},
         user_message: nil
       }}
    end)

    stub(Stripe.InvoiceMock, :pay, fn _invoice_id, _params ->
      {:error,
       %Stripe.Error{
         source: :stripe,
         code: :not_found,
         message: "No such invoice",
         request_id: nil,
         extra: %{},
         user_message: nil
       }}
    end)

    # Turnstile: always pass verification and pass through socket on refresh
    stub(TurnstileMock, :verify, fn _params, _ip ->
      {:ok, %{"success" => true}}
    end)

    stub(TurnstileMock, :refresh, fn socket -> socket end)

    Application.put_env(:ysc, :stripe_client, Ysc.TestStripeClient)
  end

  @doc """
  Makes refund helpers in this process survive a leaked `Ysc.StripeMock`.

  `:stripe_client` is VM-global Application env. `stub_default_external_mocks/0`
  resets it to `Ysc.TestStripeClient`, but a concurrent async test can switch
  it to `Ysc.StripeMock` mid-test. `create_stripe_refund_for_admin/3` then
  calls `retrieve_payment_intent/2` on the mock and raises
  `Mox.UnexpectedCallError` unless this process has a stub.

  Do not use in tests that `deny/3` `retrieve_payment_intent/2`.
  """
  def stub_stripe_mock_retrieve_for_test_refunds do
    stub(Ysc.StripeMock, :retrieve_payment_intent, fn id, opts ->
      Ysc.TestStripeClient.retrieve_payment_intent(id, opts)
    end)

    Application.put_env(:ysc, :stripe_client, Ysc.TestStripeClient)
    :ok
  end

  @doc """
  Makes deferred ticket checkout survive a leaked `Ysc.StripeMock`.

  Same VM-global `:stripe_client` race as
  `stub_stripe_mock_retrieve_for_test_refunds/0`. EventDetailsLive remaps
  `checkout=free` on a paid order to payment checkout and
  `send(self(), :create_checkout_payment_intent)`. A concurrent async test
  can switch the client to `Ysc.StripeMock` after this process's
  `stub_default_external_mocks/0` reset, so the LiveView crashes with
  `Mox.UnexpectedCallError` unless this process has a stub.

  Unlike the refund helper, this does **not** reset Application env (that
  would steal `Ysc.StripeMock` from the concurrent test that needs it).

  Do not use in tests that `deny/3` `create_payment_intent/2`.
  """
  def stub_stripe_mock_create_payment_intent_for_leaked_client do
    # Cover create/retrieve/cancel/customer so deferred checkout and any
    # follow-up handle_info after the assertion cannot raise UnexpectedCallError.
    stub_with(Ysc.StripeMock, Ysc.TestStripeClient)

    stub(Ysc.StripeMock, :create_payment_intent, fn params, _opts ->
      amount = Map.get(params, :amount) || Map.get(params, "amount") || 0

      {:ok,
       %Stripe.PaymentIntent{
         id: "pi_test_#{System.unique_integer([:positive])}",
         client_secret: "pi_test_secret",
         status: "requires_payment_method",
         amount: amount,
         currency: "usd"
       }}
    end)

    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  Returns the owner PID so it can be passed to concurrent tasks.
  """
  def setup_sandbox(tags) do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Ysc.Repo, shared: not tags[:async])

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    pid
  end

  @doc """
  Allows a process to checkout its own database connection from the sandbox.
  This is necessary for concurrent tests using Task.async_stream where each
  task needs its own connection for proper database locking behavior.

  When async: true, you must pass the owner PID from the test context.
  When async: false, the owner is available from Repo.config()[:owner].
  """
  def allow_sandbox(pid \\ self(), owner \\ nil) do
    owner =
      owner || Ysc.Repo.config()[:owner] ||
        Process.get({Ecto.Adapters.SQL.Sandbox, :owner})

    if owner do
      Ecto.Adapters.SQL.Sandbox.allow(Ysc.Repo, pid, owner)
    else
      # Fallback: use checkout which finds the owner automatically from parent
      Ecto.Adapters.SQL.Sandbox.checkout(Ysc.Repo, sandbox: true)
    end
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
