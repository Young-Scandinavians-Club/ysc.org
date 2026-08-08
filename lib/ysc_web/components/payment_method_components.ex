defmodule YscWeb.PaymentMethodComponents do
  @moduledoc """
  Shared UI for displaying a stored payment method (card, bank, Link, etc.).
  """
  use Phoenix.Component

  import YscWeb.CoreComponents

  alias YscWeb.{PaymentMethodFormatter, PaymentMethodLogo}

  attr :payment_method, :map, required: true
  attr :text_class, :string, default: "text-sm font-semibold text-zinc-700"
  attr :expiry_class, :string, default: "text-xs text-zinc-500"

  def stored_payment_method_display(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <div class="flex-shrink-0">
        <%= if logo = PaymentMethodLogo.path_for_payment_method(@payment_method) do %>
          <img
            src={logo}
            alt=""
            class="h-6 w-auto max-w-[4rem] object-contain"
            loading="lazy"
            decoding="async"
          />
        <% else %>
          <.icon
            :if={@payment_method.type == :bank_account}
            name="hero-building-library"
            class="w-6 h-6 text-zinc-700"
          />
          <.icon
            :if={@payment_method.type != :bank_account}
            name="hero-credit-card"
            class="w-6 h-6 text-zinc-700"
          />
        <% end %>
      </div>
      <div>
        <p class={@text_class}>
          {payment_method_display_text(@payment_method)}
        </p>
        <p
          :if={payment_method_shows_expiration?(@payment_method)}
          class={@expiry_class}
        >
          Expires {String.pad_leading(to_string(@payment_method.exp_month), 2, "0")} / {@payment_method.exp_year}
        </p>
        <p
          :if={
            @payment_method.type == :bank_account && @payment_method.account_type
          }
          class={@expiry_class}
        >
          {@payment_method.account_type}
        </p>
      </div>
    </div>
    """
  end

  defp payment_method_display_text(%{type: :link} = pm) do
    PaymentMethodFormatter.format_link_payment_method(
      pm.last_four,
      pm.display_brand
    )
  end

  defp payment_method_display_text(%{type: :card, last_four: last_four})
       when not is_nil(last_four) do
    "**** **** **** #{last_four}"
  end

  defp payment_method_display_text(%{
         type: :bank_account,
         bank_name: bank_name,
         last_four: last_four
       })
       when not is_nil(bank_name) and not is_nil(last_four) do
    "#{bank_name} ••••#{last_four}"
  end

  defp payment_method_display_text(%{type: :bank_account, last_four: last_four})
       when not is_nil(last_four) do
    "Bank Account ••••#{last_four}"
  end

  defp payment_method_display_text(%{type: :card}), do: "Credit Card"
  defp payment_method_display_text(%{type: :bank_account}), do: "Bank Account"
  defp payment_method_display_text(_), do: "Payment Method"

  defp payment_method_shows_expiration?(%{
         type: type,
         exp_month: exp_month,
         exp_year: exp_year
       })
       when type in [:card, :link] and not is_nil(exp_month) and
              not is_nil(exp_year),
       do: true

  defp payment_method_shows_expiration?(_), do: false
end
