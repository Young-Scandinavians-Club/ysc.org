defmodule YscWeb.Styles.App.SwiftUI do
  @moduledoc """
  SwiftUI stylesheet for the YSC application.

  Defines reusable style classes for SwiftUI components used in the LiveView Native
  iOS application, including kiosk screens, buttons, cards, and color schemes.
  """
  use LiveViewNative.Stylesheet, :swiftui

  # Add your styles here
  # Refer to your client's documentation on what the proper syntax
  # is for defining rules within classes
  ~SHEET"""
  "kiosk-screen" do
    frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    padding(56)
  end

  "kiosk-screen-leading" do
    frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    padding(48)
  end

  "kiosk-stack-560" do
    frame(maxWidth: 560)
  end

  "kiosk-stack-720" do
    frame(maxWidth: 720)
  end

  "kiosk-stack-900" do
    frame(maxWidth: 900)
  end

  "kiosk-stack-980" do
    frame(maxWidth: 980)
  end

  "kiosk-card" do
    padding(20)
    background(.secondarySystemBackground)
    cornerRadius(16)
  end

  "kiosk-card-lg" do
    padding(30)
    background(.secondarySystemBackground)
    cornerRadius(20)
  end

  "kiosk-primary-button" do
    buttonStyle(.borderedProminent)
    controlSize(.large)
  end

  "kiosk-secondary-button" do
    buttonStyle(.bordered)
    controlSize(.large)
  end

  "kiosk-primary-button-wide" do
    buttonStyle(.borderedProminent)
    controlSize(.large)
    frame(minWidth: 520)
  end

  "kiosk-primary-button-full" do
    buttonStyle(.borderedProminent)
    controlSize(.large)
    frame(maxWidth: .infinity)
  end

  "kiosk-secondary-button-full" do
    buttonStyle(.bordered)
    controlSize(.large)
    frame(maxWidth: .infinity)
  end

  "kiosk-textfield" do
    textFieldStyle(.roundedBorder)
    textInputAutocapitalization(.characters)
    autocorrectionDisabled()
    frame(height: 56)
  end

  "kiosk-textfield-52" do
    textFieldStyle(.roundedBorder)
    textInputAutocapitalization(.characters)
    autocorrectionDisabled()
    frame(height: 52)
  end

  "kiosk-chip" do
    buttonStyle(.bordered)
    controlSize(.large)
  end

  "kiosk-chip-selected" do
    buttonStyle(.borderedProminent)
    controlSize(.large)
  end

  "kiosk-checkmark" do
    font(.system(size: 88))
    foregroundStyle(.green)
  end

  "kiosk-shell" do
    frame(maxWidth: .infinity, maxHeight: .infinity)
  end

  "kiosk-left-panel" do
    padding(24)
    frame(width: 360, maxHeight: .infinity)
    background(.secondarySystemBackground)
    cornerRadius(28)
  end

  "kiosk-right-panel" do
    frame(maxWidth: .infinity, maxHeight: .infinity)
    layoutPriority(1)
  end

  "kiosk-left-image" do
    resizable()
    scaledToFill()
    frame(maxWidth: .infinity, maxHeight: .infinity)
    clipped()
  end

  "kiosk-left-overlay" do
    frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    padding(40)
  end

  "main-logo" do
    resizable()
    scaledToFit()
    frame(maxWidth: 240, maxHeight: 120)
  end

  "ysc-logo-120" do
    resizable()
    scaledToFit()
    frame(width: 120, height: 120)
  end

  "ysc-logo-160" do
    resizable()
    scaledToFit()
    frame(width: 160, height: 160)
  end

  "ysc-logo-200" do
    resizable()
    scaledToFit()
    frame(width: 200, height: 200)
  end

  "image-fail" do
    foregroundStyle(.secondary)
    frame(width: 44, height: 44)
  end

  "kiosk-home-tile-primary" do
    padding(18)
    frame(width: 190, height: 190)
    background(.systemBlue)
    cornerRadius(28)
    shadow(radius: 10)
    scaleEffect(1.0)
  end

  "kiosk-home-tile-primary:pressed" do
    scaleEffect(0.95)
    background(.systemBlue.opacity(0.85))
    cornerRadius(28)
  end

  "kiosk-home-tile-secondary" do
    padding(18)
    frame(width: 190, height: 190)
    background(.secondarySystemBackground)
    cornerRadius(28)
    shadow(radius: 6)
    scaleEffect(1.0)
  end

  "kiosk-home-tile-secondary:pressed" do
    scaleEffect(0.95)
    background(.systemGray5)
    cornerRadius(28)
  end

  "kiosk-home-tile-primary-lg" do
    padding(18)
    frame(width: 230, height: 230)
    background(.systemBlue)
    cornerRadius(32)
    shadow(radius: 14)
    scaleEffect(1.0)
  end

  "kiosk-home-tile-primary-lg:pressed" do
    scaleEffect(0.95)
    background(.systemBlue.opacity(0.85))
    cornerRadius(32)
  end

  "kiosk-reservation-card" do
    padding(16)
    frame(maxWidth: .infinity, alignment: .leading)
    background(.secondarySystemBackground)
    cornerRadius(20)
    shadow(radius: 6)
    scaleEffect(1.0)
  end

  "kiosk-reservation-card:pressed" do
    scaleEffect(0.98)
    background(.systemGray5)
    cornerRadius(20)
  end

  "kiosk-reservation-result-card" do
    padding(18)
    frame(maxWidth: .infinity, alignment: .leading)
    background(.secondarySystemBackground)
    cornerRadius(22)
    shadow(radius: 10)
    scaleEffect(1.0)
  end

  "kiosk-reservation-result-card:pressed" do
    scaleEffect(0.98)
    background(.systemGray5)
    cornerRadius(22)
  end

  "kiosk-room-pill" do
    padding(.horizontal, 10)
    padding(.vertical, 6)
    background(.systemBackground)
    cornerRadius(999)
    shadow(radius: 3)
  end

  "kiosk-room-pill-text" do
    font(.system(size: 14, weight: .semibold))
    foregroundStyle(.secondary)
  end

  "kiosk-room-map-card" do
    padding(12)
    frame(maxWidth: .infinity, alignment: .leading)
    background(.systemBackground)
    cornerRadius(14)
    shadow(radius: 3)
  end

  "kiosk-room-map-name" do
    font(.system(size: 13, weight: .bold))
    foregroundStyle(.secondary)
  end

  "kiosk-room-map-primary" do
    font(.system(size: 16, weight: .semibold))
    foregroundStyle(.primary)
  end

  "kiosk-room-map-count" do
    font(.system(size: 13, weight: .semibold))
    foregroundStyle(.tint)
  end

  "kiosk-choice-tile" do
    padding(18)
    frame(width: 240, height: 140)
    background(.secondarySystemBackground)
    cornerRadius(24)
    shadow(radius: 6)
    scaleEffect(1.0)
  end

  "kiosk-choice-tile:pressed" do
    scaleEffect(0.97)
    background(.systemGray5)
    cornerRadius(24)
  end

  "kiosk-choice-icon" do
    font(.system(size: 44))
    foregroundStyle(.tint)
  end

  "kiosk-choice-tile-placeholder" do
    padding(18)
    frame(width: 240, height: 140)
    background(.clear)
  end

  "kiosk-color-button" do
    padding(14)
    frame(maxWidth: .infinity, minHeight: 64)
    cornerRadius(16)
    shadow(radius: 4)
    scaleEffect(1.0)
  end

  "kiosk-color-button:pressed" do
    scaleEffect(0.97)
  end

  "kiosk-color-selected" do
    # Keep this parser-safe: visual emphasis without overlay/stroke.
    scaleEffect(1.05)
    shadow(radius: 12)
  end

  # Simplified color helpers (parser-friendly)
  "bg-white" do background(.white) end
  "bg-black" do background(.black) end
  "bg-gray" do background(.gray) end
  "bg-silver" do background(.systemGray4) end
  "bg-blue" do background(.blue) end
  "bg-red" do background(.red) end
  "bg-green" do background(.green) end
  "bg-orange" do background(.orange) end
  "bg-brown" do background(.brown) end
  "bg-yellow" do background(.yellow) end
  "bg-purple" do background(.purple) end

  # Custom swatches (still simple)
  "bg-beige" do background(.yellow) end
  "bg-gold" do background(.orange) end

  "fg-white" do foregroundStyle(.white) end
  "fg-black" do foregroundStyle(.black) end

  "kiosk-color-white" do
    background(.white)
    foregroundStyle(.black)
  end

  "kiosk-color-black" do
    background(.black)
    foregroundStyle(.white)
  end

  "kiosk-color-gray" do
    background(.systemGray)
    foregroundStyle(.black)
  end

  "kiosk-color-silver" do
    background(.systemGray4)
    foregroundStyle(.black)
  end

  "kiosk-color-blue" do
    background(.systemBlue)
    foregroundStyle(.white)
  end

  "kiosk-color-red" do
    background(.systemRed)
    foregroundStyle(.white)
  end

  "kiosk-color-green" do
    background(.systemGreen)
    foregroundStyle(.white)
  end

  "kiosk-color-orange" do
    background(.systemOrange)
    foregroundStyle(.black)
  end

  "kiosk-color-beige" do
    background(.yellow)
    foregroundStyle(.black)
  end

  "kiosk-color-brown" do
    background(.systemBrown)
    foregroundStyle(.white)
  end

  "kiosk-color-yellow" do
    background(.systemYellow)
    foregroundStyle(.black)
  end

  "kiosk-color-gold" do
    background(.orange)
    foregroundStyle(.black)
  end

  "kiosk-color-purple" do
    background(.systemPurple)
    foregroundStyle(.white)
  end

  "kiosk-timeline" do
    padding(12)
  end

  "kiosk-timeline-icon" do
    font(.system(size: 18, weight: .semibold))
    foregroundStyle(.secondary)
  end

  "kiosk-timeline-icon-current" do
    foregroundStyle(.tint)
  end

  "kiosk-timeline-icon-done" do
    foregroundStyle(.green)
  end

  "kiosk-timeline-label" do
    font(.system(size: 16, weight: .semibold))
    foregroundStyle(.secondary)
  end

  "kiosk-timeline-label-current" do
    foregroundStyle(.primary)
  end

  "kiosk-timeline-label-done" do
    foregroundStyle(.primary)
  end

  "kiosk-timeline-sep" do
    font(.system(size: 14, weight: .semibold))
    foregroundStyle(.tertiary)
  end

  # --- Concierge / web-design-language translation (parser-safe) ---
  "kiosk-bg" do
    ignoresSafeArea()
  end

  "bg-secondary-system-background" do
    background(.secondarySystemBackground)
  end

  "kiosk-card-concierge" do
    padding(24)
    background(.white)
    cornerRadius(24)
    shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
  end

  "ysc-masthead-label" do
    font(.system(size: 12, weight: .black))
    foregroundStyle(.blue)
    kerning(2.0)
    textCase(.uppercase)
  end

  "ysc-h1" do
    font(.system(size: 44, weight: .black))
    foregroundStyle(.primary)
  end

  "ysc-h2" do
    font(.system(size: 28, weight: .black))
    foregroundStyle(.primary)
  end

  "ysc-body" do
    font(.body)
    foregroundStyle(.secondary)
    lineSpacing(4)
  end

  "kiosk-timeline-pill" do
    padding(.horizontal, 16)
    padding(.vertical, 8)
    background(.secondarySystemBackground)
    cornerRadius(99)
  end

  "kiosk-primary-btn" do
    buttonStyle(.borderedProminent)
    controlSize(.large)
    fontWeight(.bold)
  end

  "car-grid-item" do
    frame(maxWidth: .infinity, minHeight: 100)
    cornerRadius(20)
    shadow(radius: 2)
  end

  # Shape fill helpers for RoundedRectangle
  "fill-white" do foregroundStyle(.white) end
  "fill-black" do foregroundStyle(.black) end
  "fill-gray" do foregroundStyle(.gray) end
  "fill-blue" do foregroundStyle(.blue) end
  "fill-red" do foregroundStyle(.red) end
  "fill-green" do foregroundStyle(.green) end
  "fill-brown" do foregroundStyle(.brown) end
  "fill-orange" do foregroundStyle(.orange) end
  "fill-purple" do foregroundStyle(.purple) end
  "fill-yellow" do foregroundStyle(.yellow) end
  "fill-secondary-system-background" do fill(.secondarySystemBackground) end
  "fill-gray-opacity-75" do foregroundStyle(.gray.opacity(0.75)) end
  "fill-black-opacity-10" do foregroundStyle(.black.opacity(0.10)) end
  "fill-orange-opacity-90" do foregroundStyle(.orange.opacity(0.9)) end

  # NOTE: Avoid overlay/stroke in stylesheet (parser can drop rules).
  "selected-border" do
    background(.blue.opacity(0.12))
    scaleEffect(1.05)
    shadow(radius: 8)
  end
  """

  # If you need to have greater control over how your style rules are created
  # you can use the function defintion style which is more verbose but allows
  # for more fine-grained controled
  #
  # This example shows what is not possible within the more concise ~SHEET
  # use `<Text class="frame:w100:h200" />` allows for a setting
  # of both the `width` and `height` values.

  # def class("frame:" <> dims) do
  #   [width] = Regex.run(~r/w(\d+)/, dims, capture: :all_but_first)
  #   [height] = Regex.run(~r/h(\d+)/, dims, capture: :all_but_first)

  #   ~RULES"""
  #   frame(width: {width}, height: {height})
  #   """
  # end
end
