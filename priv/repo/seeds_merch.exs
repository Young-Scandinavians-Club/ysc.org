# Seeds the merch shop catalog for local development.
#
#     mix run priv/repo/seeds_merch.exs
#
# Without a PRINTFUL_API_TOKEN, dev uses the built-in fake Printful
# (Ysc.Printful.DemoClient), so this works with no account. With a token it
# syncs your real Printful test store instead.
#
# Product images are copied into the media library by downloading them from the
# running web server, so start `mix phx.server` first for images to appear;
# otherwise products are created with the placeholder and you can press
# "Sync from Printful" at /admin/merch once the server is up.

alias Ysc.Accounts.User
alias Ysc.Merch
alias Ysc.Repo

admin = Repo.get_by(User, email: "admin@ysc.org")

if is_nil(admin) do
  IO.puts("No admin@ysc.org user found. Run `mix run priv/repo/seeds.exs` first.")
else
  mode = if Ysc.Printful.demo_mode?(), do: "demo Printful", else: "Printful"
  IO.puts("Syncing merch catalog from #{mode}...")

  case Merch.sync_catalog(admin) do
    {:ok, summary} ->
      IO.puts(
        "Synced #{summary.products} products (#{summary.variants} variants), " <>
          "#{summary.images_failed} images could not be imported."
      )

      if summary.images_failed > 0 do
        IO.puts("Start the server (mix phx.server) and press Sync at /admin/merch to import images.")
      end

    {:error, error} ->
      IO.puts("Merch sync failed: #{Exception.message(error)}")
  end
end
