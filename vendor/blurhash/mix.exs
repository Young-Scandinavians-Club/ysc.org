defmodule BlurHash.MixProject do
  use Mix.Project

  def project do
    [
      app: :blurhash,
      version: "2.0.0",
      elixir: "~> 1.7",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: []
    ]
  end

  def application do
    []
  end
end
