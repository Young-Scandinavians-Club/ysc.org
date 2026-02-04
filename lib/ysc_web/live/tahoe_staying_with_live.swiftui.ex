defmodule YscWeb.TahoeStayingWithLive.SwiftUI do
  use YscNative, [:render_component, format: :swiftui]

  embed_templates "live/swiftui/tahoe_staying_with_live*"
end
