defmodule YscWeb.AdminHelp.Guide do
  @moduledoc """
  Behaviour for interactive admin help guides.

  Each guide is a step-by-step wizard with optional FAQ and troubleshooting text
  for the LLM step clarifier.
  """

  @type hotspot_area :: :content | :sidebar | :viewport

  @type hotspot_style :: :highlight | :hint

  @type hotspot_layout :: %{
          required(:x) => number(),
          required(:y) => number(),
          required(:w) => number(),
          required(:h) => number(),
          optional(:area) => hotspot_area()
        }

  @type hotspot ::
          hotspot_layout()
          | %{
              required(:label) => String.t(),
              optional(:style) => hotspot_style(),
              optional(:expanded) => hotspot_layout(),
              optional(:collapsed) => hotspot_layout()
            }
          | %{
              required(:label) => String.t(),
              required(:x) => number(),
              required(:y) => number(),
              required(:w) => number(),
              required(:h) => number(),
              optional(:area) => hotspot_area(),
              optional(:style) => hotspot_style(),
              optional(:expanded) => hotspot_layout(),
              optional(:collapsed) => hotspot_layout()
            }

  @type step :: %{
          required(:title) => String.t(),
          required(:body) => String.t(),
          optional(:image) => String.t(),
          optional(:image_scroll) => String.t(),
          optional(:hotspots) => [hotspot()],
          optional(:public_image) => String.t(),
          optional(:public_image_scroll) => String.t(),
          optional(:public_hotspots) => [hotspot()],
          optional(:cta) => %{label: String.t(), path: String.t()}
        }

  @type audience :: :admin | :volunteer

  @callback slug() :: String.t()
  @callback title() :: String.t()
  @callback summary() :: String.t()
  @callback category() :: atom()
  @callback audience() :: [audience()]
  @callback steps() :: [step()]

  @callback faq() :: [{String.t(), String.t()}]
  @callback troubleshooting() :: [String.t()]

  defmacro __using__(_opts) do
    quote do
      @behaviour YscWeb.AdminHelp.Guide

      def faq, do: []
      def troubleshooting, do: []

      defoverridable faq: 0, troubleshooting: 0
    end
  end

  @category_labels %{
    getting_started: "Getting started",
    posts: "Posts",
    newsletters: "Newsletters",
    events: "Events",
    media: "Media",
    day_of: "Day-of operations"
  }

  @category_order [
    :getting_started,
    :posts,
    :newsletters,
    :events,
    :media,
    :day_of
  ]

  def category_label(category) when is_atom(category) do
    Map.get(@category_labels, category, "Other")
  end

  def categories, do: @category_order
end
