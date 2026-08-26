defmodule YscWeb.NewsletterComponents do
  @moduledoc """
  Public newsletter signup and member subscription widgets.

  These are imported automatically via `YscWeb` HTML helpers. Guest signup
  submits `"subscribe_newsletter"`; member toggles default to
  `"toggle_newsletter_subscription"`.
  """
  use Phoenix.Component

  import YscWeb.CoreComponents

  @doc """
  Guest email signup form with Turnstile, error, and confirmation-sent states.

  Used on the home page and newsletter archive.

  ## Examples

      <.newsletter_subscribe_form
        id="home-newsletter-form"
        email={@newsletter_email}
        submitted={@newsletter_submitted}
        error={@newsletter_error}
      >
        <:footer>
          <p class="mt-4 text-sm text-zinc-600">We don't spam.</p>
        </:footer>
      </.newsletter_subscribe_form>
  """
  attr :id, :string, required: true
  attr :email, :string, default: ""
  attr :submitted, :boolean, default: false
  attr :error, :string, default: nil
  attr :class, :any, default: nil
  attr :labelledby, :string, default: nil
  attr :describedby, :string, default: nil
  slot :footer

  def newsletter_subscribe_form(assigns) do
    ~H"""
    <form
      id={@id}
      phx-submit="subscribe_newsletter"
      class={@class}
      aria-labelledby={@labelledby}
      aria-describedby={@describedby}
    >
      <div class="space-y-4">
        <div class="flex flex-col sm:flex-row gap-3 sm:gap-4">
          <div class="flex-1 min-w-0">
            <label for="newsletter-email" class="sr-only">
              Email address for newsletter signup
            </label>
            <input
              type="email"
              id="newsletter-email"
              name="email"
              autocomplete="email"
              value={@email}
              class="w-full px-4 py-3 border border-zinc-300 rounded text-zinc-900 focus:ring-2 focus:ring-blue-700 focus:border-blue-700 bg-white"
              placeholder="Email address"
              required
              disabled={@submitted}
              aria-invalid={@error != nil}
              aria-errormessage={
                if @error != nil, do: "newsletter-error", else: nil
              }
            />
          </div>
          <.button
            :if={!@submitted}
            type="submit"
            phx-disable-with="Subscribing..."
            class="px-6 py-3 shrink-0"
            aria-label="Subscribe to newsletter"
          >
            Subscribe
          </.button>
        </div>

        <div class="w-full flex justify-center">
          <Turnstile.widget appearance="interaction-only" theme="light" />
        </div>
      </div>

      <p
        :if={@error}
        id="newsletter-error"
        class="mt-3 text-sm text-red-600"
        role="alert"
      >
        {@error}
      </p>

      <div :if={@submitted} class="mt-3 text-emerald-600">
        <div class="flex items-center justify-center gap-2">
          <.icon name="hero-check-circle" class="w-5 h-5 shrink-0" />
          <span class="font-medium">
            You're one step away! Check your email to confirm your subscription.
          </span>
        </div>
        <p class="mt-2 text-sm text-zinc-600">
          Look for an email from YSC with the subject "Action Required: Please confirm your subscription." If you don't see it in a couple minutes, check your spam or promotions folder.
        </p>
      </div>

      {render_slot(@footer)}
    </form>
    """
  end

  @doc """
  Logged-in member subscribe/unsubscribe control.

  `:card` is the bordered archive widget. `:compact` is the home dashboard row.

  ## Examples

      <.newsletter_member_status subscribed={@newsletter_subscribed} layout={:compact} />

      <.newsletter_member_status
        id="newsletter-member-status"
        subscribed={@user_subscribed}
        event="toggle_subscription"
      />
  """
  attr :id, :string, default: nil
  attr :subscribed, :boolean, required: true
  attr :layout, :atom, default: :card, values: [:card, :compact]
  attr :event, :string, default: "toggle_newsletter_subscription"

  def newsletter_member_status(%{layout: :compact} = assigns) do
    ~H"""
    <div id={@id} class="flex items-center gap-3">
      <div class={[
        "flex items-center justify-center w-9 h-9 rounded-full shrink-0",
        if(@subscribed, do: "bg-emerald-100", else: "bg-zinc-100")
      ]}>
        <.icon
          name={if(@subscribed, do: "hero-check", else: "hero-envelope")}
          class={[
            "w-4 h-4",
            if(@subscribed, do: "text-emerald-600", else: "text-zinc-500")
          ]}
        />
      </div>
      <div class="min-w-0 flex-1">
        <p class="font-semibold text-zinc-900 text-sm">
          {if @subscribed, do: "Subscribed", else: "Not subscribed"}
        </p>
        <p class="text-xs text-zinc-500 mt-0.5">
          {if @subscribed,
            do: "You'll get new newsletters in your inbox.",
            else: "Get news & updates in your inbox."}
        </p>
      </div>
      <button
        type="button"
        phx-click={@event}
        phx-disable-with="Saving..."
        class="shrink-0 text-xs font-bold text-blue-600 hover:underline"
      >
        {if @subscribed, do: "Unsubscribe", else: "Subscribe"}
      </button>
    </div>
    """
  end

  def newsletter_member_status(assigns) do
    ~H"""
    <div
      id={@id}
      class="rounded-xl border border-zinc-200 bg-zinc-50 px-6 py-6 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4"
    >
      <div class="flex items-center gap-3">
        <div class={[
          "flex items-center justify-center w-10 h-10 rounded-full shrink-0",
          if(@subscribed, do: "bg-emerald-100", else: "bg-zinc-200")
        ]}>
          <.icon
            name={if(@subscribed, do: "hero-check", else: "hero-envelope")}
            class={[
              "w-5 h-5",
              if(@subscribed, do: "text-emerald-600", else: "text-zinc-500")
            ]}
          />
        </div>
        <div>
          <p class="font-semibold text-zinc-900 text-sm">
            {if @subscribed, do: "You're subscribed", else: "You're not subscribed"}
          </p>
          <p class="text-xs text-zinc-500 mt-0.5">
            {if @subscribed,
              do: "You'll receive new newsletters in your inbox.",
              else: "Subscribe to receive future newsletters in your inbox."}
          </p>
        </div>
      </div>
      <.button
        phx-click={@event}
        class={
          if(@subscribed,
            do:
              "shrink-0 px-4 py-2 text-sm !bg-white !text-zinc-700 border border-zinc-300 hover:!bg-zinc-100",
            else: "shrink-0 px-4 py-2 text-sm"
          )
        }
        phx-disable-with="Saving..."
      >
        {if @subscribed, do: "Unsubscribe", else: "Subscribe"}
      </.button>
    </div>
    """
  end
end
