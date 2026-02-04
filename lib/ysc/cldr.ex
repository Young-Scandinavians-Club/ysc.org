defmodule Ysc.Cldr do
  @moduledoc """
  Cldr configuration module.

  Configures the Cldr library for internationalization and localization support.
  """
  use Cldr,
    locales: [:en],
    default_locale: :en
end
