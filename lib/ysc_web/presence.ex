defmodule YscWeb.Presence do
  use Phoenix.Presence,
    otp_app: :ysc,
    pubsub_server: Ysc.PubSub
end
