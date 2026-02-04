defmodule YscWeb.PropertyCheckInLive.SwiftUI do
  use YscNative, [:render_component, format: :swiftui]

  embed_templates "live/swiftui/*"
end
