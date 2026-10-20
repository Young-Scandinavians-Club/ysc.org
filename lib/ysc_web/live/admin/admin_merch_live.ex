defmodule YscWeb.AdminMerchLive do
  @moduledoc """
  Admin view of the merch shop catalog.

  Products are designed and priced in Printful; this page syncs them into the
  shop, and lets full admins hide a product, reorder it, and write the
  description members see.
  """
  use YscWeb, :admin_live_view

  on_mount {YscWeb.UserAuth, :ensure_full_admin}

  import YscWeb.AdminMerchComponents, only: [merch_tabs: 1, wip_banner: 1]

  alias Ysc.Media.Image
  alias Ysc.Merch
  alias Ysc.Merch.AdminOrders

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active_page, :merch)
     |> assign(:page_title, "Merch")
     |> assign(:syncing?, false)
     |> assign(:registering_webhooks?, false)
     |> assign(:demo_mode?, Ysc.Printful.demo_mode?())
     |> assign(:editing_product, nil)
     |> assign(:form, nil)
     |> assign(:attention_count, AdminOrders.needs_attention_count())
     |> load_products()}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case Merch.get_admin_product(id) do
      nil ->
        {:noreply, push_patch(socket, to: ~p"/admin/merch")}

      product ->
        {:noreply,
         socket
         |> assign(:editing_product, product)
         |> assign(:form, to_form(Merch.change_product(product)))}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket |> assign(:editing_product, nil) |> assign(:form, nil)}
  end

  @impl true
  def handle_event("sync", _params, %{assigns: %{syncing?: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("sync", _params, socket) do
    uploader = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(:syncing?, true)
     |> start_async(:sync_catalog, fn -> Merch.sync_catalog(uploader) end)}
  end

  def handle_event(
        "register_webhooks",
        _params,
        %{assigns: %{registering_webhooks?: true}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event("register_webhooks", _params, socket) do
    {:noreply,
     socket
     |> assign(:registering_webhooks?, true)
     |> start_async(:register_webhooks, fn -> Ysc.Merch.Webhooks.register() end)}
  end

  def handle_event("validate", %{"product" => params}, socket) do
    form =
      socket.assigns.editing_product
      |> Merch.change_product(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"product" => params}, socket) do
    case Merch.update_product(socket.assigns.editing_product, params) do
      {:ok, _product} ->
        {:noreply,
         socket
         |> YscWeb.Flash.put_toast(:info, "Product updated.")
         |> load_products()
         |> push_patch(to: ~p"/admin/merch")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event(
        "photo_color",
        %{"photo_id" => photo_id, "color" => color},
        socket
      ) do
    case Merch.set_photo_color(photo_id, color) do
      {:ok, _} -> {:noreply, refresh_editing(socket)}
      {:error, reason} -> {:noreply, photo_error(socket, reason)}
    end
  end

  def handle_event("photo_first", %{"id" => photo_id}, socket) do
    case Merch.move_photo_first(photo_id) do
      :ok -> {:noreply, refresh_editing(socket)}
      {:error, reason} -> {:noreply, photo_error(socket, reason)}
    end
  end

  def handle_event("photo_remove", %{"id" => photo_id}, socket) do
    case Merch.remove_product_photo(photo_id) do
      :ok -> {:noreply, refresh_editing(socket)}
      {:error, reason} -> {:noreply, photo_error(socket, reason)}
    end
  end

  def handle_event("toggle_visibility", %{"id" => id}, socket) do
    product = Enum.find(socket.assigns.products, &(&1.id == id))

    case product &&
           Merch.update_product(product, %{status: next_status(product)}) do
      {:ok, _} -> {:noreply, load_products(socket)}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {YscWeb.MediaPickerComponent, :merch_add_photo, image_id},
        socket
      )
      when is_binary(image_id) do
    case socket.assigns.editing_product &&
           Merch.add_product_photo(socket.assigns.editing_product, image_id) do
      {:ok, _photo} ->
        {:noreply, refresh_editing(socket)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         YscWeb.Flash.put_toast(
           socket,
           :info,
           "That photo is already on this product."
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info(
        {YscWeb.MediaPickerComponent, :merch_add_photo, image_ids},
        socket
      )
      when is_list(image_ids) do
    results =
      case socket.assigns.editing_product do
        nil ->
          []

        product ->
          Enum.map(image_ids, &Merch.add_product_photo(product, &1))
      end

    socket = refresh_editing(socket)

    if results == [] do
      {:noreply, socket}
    else
      {:noreply,
       YscWeb.Flash.put_toast(
         socket,
         if(Enum.any?(results, &failed_photo?/1), do: :error, else: :info),
         add_photos_summary(results)
       )}
    end
  end

  def handle_info(
        {YscWeb.MediaPickerComponent, :merch_add_photo, :cleared},
        socket
      ),
      do: {:noreply, socket}

  defp failed_photo?({:error, %Ecto.Changeset{} = changeset}),
    do: not duplicate_photo?(changeset)

  defp failed_photo?(_result), do: false

  defp duplicate_photo?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_message, opts}} ->
      opts[:constraint] == :unique
    end)
  end

  defp add_photos_summary(results) do
    added = Enum.count(results, &match?({:ok, _}, &1))

    duplicates =
      Enum.count(results, fn
        {:error, %Ecto.Changeset{} = changeset} -> duplicate_photo?(changeset)
        _ -> false
      end)

    failed = length(results) - added - duplicates

    [
      "Added #{added} #{if added == 1, do: "photo", else: "photos"}",
      if(duplicates > 0, do: "#{duplicates} already on this product"),
      if(failed > 0, do: "#{failed} could not be added")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("; ")
    |> Kernel.<>(".")
  end

  # The photo list is part of the product being edited; reload it after a change.
  defp refresh_editing(socket) do
    socket = load_products(socket)

    case socket.assigns.editing_product &&
           Merch.get_admin_product(socket.assigns.editing_product.id) do
      nil -> socket
      product -> assign(socket, :editing_product, product)
    end
  end

  defp photo_error(socket, :managed_by_printful) do
    YscWeb.Flash.put_toast(
      socket,
      :info,
      "That photo comes from Printful and updates with each sync."
    )
  end

  defp photo_error(socket, _reason) do
    socket
    |> refresh_editing()
    |> YscWeb.Flash.put_toast(:error, "That photo no longer exists.")
  end

  defp product_colors(product),
    do: Ysc.Merch.VariantSelection.colors(product.variants)

  @impl true
  def handle_async(:sync_catalog, {:ok, {:ok, summary}}, socket) do
    message =
      "Synced #{summary.products} products (#{summary.variants} variants)." <>
        if(summary.removed > 0, do: " #{summary.removed} removed.", else: "") <>
        if(summary.failed > 0,
          do: " #{summary.failed} could not be fetched; try again.",
          else: ""
        ) <>
        if(summary.images_failed > 0,
          do:
            " #{summary.images_failed} images could not be imported; try again.",
          else: ""
        )

    kind =
      if summary.failed > 0 or summary.images_failed > 0,
        do: :warning,
        else: :info

    {:noreply,
     socket
     |> assign(:syncing?, false)
     |> YscWeb.Flash.put_toast(kind, message)
     |> load_products()}
  end

  def handle_async(:sync_catalog, {:ok, {:error, error}}, socket) do
    {:noreply,
     socket
     |> assign(:syncing?, false)
     |> YscWeb.Flash.put_toast(
       :error,
       "Sync failed: #{Exception.message(error)}"
     )}
  end

  def handle_async(:register_webhooks, {:ok, {:ok, masked_url}}, socket) do
    {:noreply,
     socket
     |> assign(:registering_webhooks?, false)
     |> YscWeb.Flash.put_toast(
       :info,
       "Printful will now tell us when orders ship. Callback: #{masked_url}",
       title: "Webhooks registered"
     )}
  end

  def handle_async(:register_webhooks, {:ok, {:error, :no_secret}}, socket) do
    {:noreply,
     socket
     |> assign(:registering_webhooks?, false)
     |> YscWeb.Flash.put_toast(
       :error,
       "Set PRINTFUL_WEBHOOK_SECRET first. It becomes part of the callback URL.",
       title: "Webhooks not registered"
     )}
  end

  def handle_async(:register_webhooks, {:ok, {:error, error}}, socket) do
    {:noreply,
     socket
     |> assign(:registering_webhooks?, false)
     |> YscWeb.Flash.put_toast(
       :error,
       "Printful said: #{Exception.message(error)}",
       title: "Webhooks not registered"
     )}
  end

  def handle_async(:register_webhooks, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:registering_webhooks?, false)
     |> YscWeb.Flash.put_toast(
       :error,
       "Registering webhooks failed unexpectedly. Try again."
     )}
  end

  def handle_async(:sync_catalog, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:syncing?, false)
     |> YscWeb.Flash.put_toast(:error, "Sync failed unexpectedly. Try again.")}
  end

  defp load_products(socket) do
    products = Merch.list_admin_products()

    socket
    |> assign(:products, products)
    |> assign(:last_synced_at, last_synced_at(products))
  end

  defp last_synced_at([]), do: nil

  defp last_synced_at(products) do
    products
    |> Enum.map(& &1.synced_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp next_status(%{status: :active}), do: :hidden
  defp next_status(_), do: :active

  defp available_variant_count(product),
    do: Enum.count(product.variants, & &1.available)

  defp price_range(product) do
    prices =
      product.variants
      |> Enum.filter(& &1.available)
      |> Enum.map(& &1.retail_price)

    case Enum.sort_by(prices, &Money.to_decimal/1, Decimal) do
      [] ->
        "-"

      sorted ->
        low = List.first(sorted)
        high = List.last(sorted)

        if Money.equal?(low, high),
          do: Money.to_string!(low),
          else: "#{Money.to_string!(low)} – #{Money.to_string!(high)}"
    end
  end

  defp status_label(%{status: :active}), do: "Visible"
  defp status_label(_), do: "Hidden"

  defp status_badge_type(%{status: :active}), do: "green"
  defp status_badge_type(_), do: "zinc"

  attr :product, :map, required: true
  attr :menu_id, :string, required: true
  attr :suffix, :string, default: ""

  defp merch_row_actions(assigns) do
    ~H"""
    <.row_actions_dropdown id={@menu_id} label="Product actions">
      <.dropdown_menu_item
        id={"edit-merch-product#{@suffix}-#{@product.id}"}
        icon="hero-pencil-square"
        patch={~p"/admin/merch/products/#{@product.id}/edit"}
      >
        Edit
      </.dropdown_menu_item>
      <.dropdown_menu_item
        :if={@product.status == :active}
        id={"view-merch-product#{@suffix}-#{@product.id}"}
        icon="hero-arrow-top-right-on-square"
        href={~p"/shop/products/#{@product.id}"}
        target="_blank"
        rel="noopener noreferrer"
      >
        View in shop
      </.dropdown_menu_item>
      <.dropdown_menu_item
        id={"toggle-merch-product#{@suffix}-#{@product.id}"}
        icon={
          if(@product.status == :active, do: "hero-eye-slash", else: "hero-eye")
        }
        phx-click="toggle_visibility"
        phx-value-id={@product.id}
      >
        {if @product.status == :active, do: "Hide from shop", else: "Show in shop"}
      </.dropdown_menu_item>
    </.row_actions_dropdown>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.side_menu
      active_page={@active_page}
      user={@current_user}
      role={@admin_role}
    >
      <div class="flex flex-wrap items-start justify-between gap-4 py-6">
        <div>
          <.admin_page_title subtitle="Products and prices are managed in Printful. Sync to pull in changes.">
            Merch
          </.admin_page_title>
        </div>

        <div class="flex items-center gap-3">
          <.button
            id="register-merch-webhooks"
            phx-click="register_webhooks"
            disabled={@registering_webhooks?}
            variant="outline"
            data-confirm="Tell Printful to send order and shipping updates to this site?"
          >
            <.icon name="hero-bell-alert" class="w-5 h-5" />
            {if @registering_webhooks?,
              do: "Registering…",
              else: "Register webhooks"}
          </.button>
          <.button id="sync-merch-catalog" phx-click="sync" disabled={@syncing?}>
            <.icon
              name="hero-arrow-path"
              class={["w-5 h-5", @syncing? && "animate-spin"]}
            />
            {if @syncing?, do: "Syncing…", else: "Sync from Printful"}
          </.button>
        </div>
      </div>

      <div class="w-full pb-16 pt-4">
        <.wip_banner />

        <p
          :if={@demo_mode?}
          id="merch-demo-banner"
          class="mb-6 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900"
        >
          Demo mode: this is a built-in fake Printful. Orders placed here never reach a real printer.
          Set <code>PRINTFUL_API_TOKEN</code> to use a real Printful store.
        </p>

        <.merch_tabs active={:products} attention_count={@attention_count} />

        <p id="merch-last-synced" class="py-4 text-sm text-zinc-500">
          <%= if @last_synced_at do %>
            Last synced {Calendar.strftime(@last_synced_at, "%b %-d, %Y %H:%M UTC")}
          <% else %>
            Not synced yet.
          <% end %>
        </p>

        <.admin_list_empty_state
          :if={@products == []}
          id="merch-empty"
          title="No products yet"
          suggestion="Create products in Printful, then press Sync from Printful."
        />

        <div :if={@products != []}>
          <%!-- Mobile card view --%>
          <.admin_mobile_list id="admin-merch-mobile">
            <.admin_mobile_list_card
              :for={product <- @products}
              id={"merch-product-card-#{product.id}"}
              footer_align={:between}
            >
              <.link
                patch={~p"/admin/merch/products/#{product.id}/edit"}
                class="mb-3 flex cursor-pointer items-center gap-3"
              >
                <img
                  src={Image.thumbnail_path_with_fallback(product.image)}
                  alt=""
                  class="size-14 shrink-0 rounded-lg bg-zinc-100 object-cover"
                  loading="lazy"
                />
                <div class="min-w-0">
                  <h3 class="truncate text-base text-zinc-900 type-subhead">
                    {product.name}
                  </h3>
                  <p class="text-sm text-zinc-600">
                    {available_variant_count(product)} of {length(product.variants)} variants · {price_range(
                      product
                    )}
                  </p>
                  <p
                    :if={product.removed_from_printful_at}
                    class="text-sm text-amber-700"
                  >
                    No longer in Printful
                  </p>
                </div>
              </.link>

              <:footer>
                <div>
                  <span id={"merch-product-card-status-#{product.id}"}>
                    <.badge type={status_badge_type(product)}>
                      {status_label(product)}
                    </.badge>
                  </span>
                </div>
                <.merch_row_actions
                  product={product}
                  menu_id={"merch-menu-mob-#{product.id}"}
                  suffix="-mob"
                />
              </:footer>
            </.admin_mobile_list_card>
          </.admin_mobile_list>

          <%!-- Desktop table view --%>
          <div class="hidden md:block">
            <table id="admin_merch_products_list">
              <thead>
                <tr>
                  <th>Product</th>
                  <th>Variants</th>
                  <th>Price</th>
                  <th>Photos</th>
                  <th>Status</th>
                  <th><span class="sr-only">Actions</span></th>
                </tr>
              </thead>
              <tbody id="merch-products">
                <tr
                  :for={product <- @products}
                  id={"merch-product-#{product.id}"}
                  class="cursor-pointer"
                >
                  <td phx-click={
                    JS.patch(~p"/admin/merch/products/#{product.id}/edit")
                  }>
                    <div class="flex items-center gap-3">
                      <img
                        src={Image.thumbnail_path_with_fallback(product.image)}
                        alt=""
                        class="size-10 shrink-0 rounded-lg bg-zinc-100 object-cover"
                        loading="lazy"
                      />
                      <div>
                        <p class="text-sm font-semibold">{product.name}</p>
                        <p
                          :if={product.removed_from_printful_at}
                          class="text-xs text-amber-700"
                        >
                          No longer in Printful
                        </p>
                      </div>
                    </div>
                  </td>
                  <td phx-click={
                    JS.patch(~p"/admin/merch/products/#{product.id}/edit")
                  }>
                    {available_variant_count(product)} of {length(product.variants)}
                  </td>
                  <td phx-click={
                    JS.patch(~p"/admin/merch/products/#{product.id}/edit")
                  }>
                    {price_range(product)}
                  </td>
                  <td phx-click={
                    JS.patch(~p"/admin/merch/products/#{product.id}/edit")
                  }>
                    {length(product.gallery_images)}
                  </td>
                  <td phx-click={
                    JS.patch(~p"/admin/merch/products/#{product.id}/edit")
                  }>
                    <span id={"merch-product-status-#{product.id}"}>
                      <.badge type={status_badge_type(product)}>
                        {status_label(product)}
                      </.badge>
                    </span>
                  </td>
                  <td class="text-right">
                    <.merch_row_actions
                      product={product}
                      menu_id={"merch-menu-#{product.id}"}
                      suffix=""
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <.modal
        :if={@editing_product}
        id="merch-product-modal"
        show
        on_cancel={JS.patch(~p"/admin/merch")}
      >
        <h2 class="type-title text-xl text-zinc-900 mb-4">
          {@editing_product.name}
        </h2>
        <.form
          for={@form}
          id="merch-product-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.input
            field={@form[:description]}
            type="textarea"
            label="Description"
            rows="4"
          />
          <.input
            field={@form[:status]}
            type="select"
            label="Visibility"
            options={[{"Visible in shop", :active}, {"Hidden", :hidden}]}
          />
          <.input
            field={@form[:sort_order]}
            type="number"
            label="Sort order (lower shows first)"
          />
          <div class="flex justify-end gap-2">
            <.button
              type="button"
              variant="outline"
              phx-click={JS.patch(~p"/admin/merch")}
            >
              Cancel
            </.button>
            <.button type="submit" id="save-merch-product">Save</.button>
          </div>
        </.form>

        <section id="merch-photos" class="mt-8 space-y-4 pt-2">
          <div>
            <h3 class="type-subhead text-lg text-zinc-900">Photos</h3>
            <p class="text-sm text-zinc-500">
              Photos tied to a color show only while that color is selected. Printful's own photos
              refresh with each sync; upload several at once or pick from the media library.
            </p>
          </div>

          <p
            :if={@editing_product.gallery_images == []}
            id="merch-photos-empty"
            class="text-sm text-zinc-500"
          >
            No photos yet.
          </p>

          <ul :if={@editing_product.gallery_images != []} class="space-y-3">
            <li
              :for={photo <- @editing_product.gallery_images}
              id={"merch-photo-#{photo.id}"}
              class="flex flex-wrap items-center gap-4 rounded-xl bg-zinc-50 p-3"
            >
              <img
                src={Image.thumbnail_path_with_fallback(photo.image)}
                alt=""
                class="size-16 shrink-0 rounded-lg bg-zinc-100 object-cover"
                loading="lazy"
              />

              <div class="min-w-0 flex-1">
                <p class="truncate text-sm text-zinc-900">
                  {photo.image.title || "Untitled"}
                </p>
                <p :if={photo.source == :printful} class="text-xs text-zinc-500">
                  From Printful · {photo.color || "all colors"}
                </p>
              </div>

              <form
                :if={photo.source == :admin}
                id={"merch-photo-color-form-#{photo.id}"}
                phx-change="photo_color"
              >
                <input type="hidden" name="photo_id" value={photo.id} />
                <label for={"merch-photo-color-#{photo.id}"} class="sr-only">Color</label>
                <select
                  id={"merch-photo-color-#{photo.id}"}
                  name="color"
                  class="rounded-lg border-zinc-300 py-1.5 text-sm"
                >
                  <option value="" selected={is_nil(photo.color)}>
                    All colors
                  </option>
                  <option
                    :for={color <- product_colors(@editing_product)}
                    value={color}
                    selected={photo.color == color}
                  >
                    {color}
                  </option>
                </select>
              </form>

              <div class="flex items-center gap-1">
                <button
                  type="button"
                  id={"merch-photo-first-#{photo.id}"}
                  phx-click="photo_first"
                  phx-value-id={photo.id}
                  class="rounded-lg px-3 py-1.5 text-sm text-zinc-600 hover:bg-zinc-200"
                >
                  Make first
                </button>
                <button
                  :if={photo.source == :admin}
                  type="button"
                  id={"merch-photo-remove-#{photo.id}"}
                  phx-click="photo_remove"
                  phx-value-id={photo.id}
                  class="rounded-lg px-3 py-1.5 text-sm text-red-600 hover:bg-red-50"
                >
                  Remove
                </button>
              </div>
            </li>
          </ul>

          <div id="merch-add-photo">
            <.live_component
              module={YscWeb.MediaPickerComponent}
              id={:merch_add_photo}
              user_id={@current_user.id}
              image_id={nil}
              multiple
            />
          </div>
        </section>
      </.modal>
    </.side_menu>
    """
  end
end
