defmodule YscWeb.Layouts.SwiftUI do
  @moduledoc """
  SwiftUI layout templates for the YSC application.

  Provides layout templates for the LiveView Native SwiftUI format, embedding
  templates from the layouts_swiftui directory.
  """
  use YscNative, [:layout, format: :swiftui]

  embed_templates "layouts_swiftui/*"
end
