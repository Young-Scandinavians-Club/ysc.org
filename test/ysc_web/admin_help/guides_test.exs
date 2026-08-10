defmodule YscWeb.AdminHelp.GuidesTest do
  @moduledoc """
  Tests for the individual admin help guide modules under `YscWeb.AdminHelp.Guides`.

  Each guide module is a data-literal wizard (slug/title/summary/category/audience/
  steps/faq/troubleshooting). `Ysc.AdminHelp.RegistryTest` already exercises
  `steps/0` for every guide; this file rounds out coverage by exercising every
  callback - including `faq/0` and `troubleshooting/0`, which are not otherwise
  called anywhere in the test suite - and asserts basic structural invariants on
  the returned data.
  """
  use ExUnit.Case, async: true

  alias YscWeb.AdminHelp.{Guide, Registry}

  @guides Registry.all()

  describe "guide callbacks" do
    test "every guide implements the full behaviour with sane data" do
      for mod <- @guides do
        assert is_binary(mod.slug()) and mod.slug() != ""
        assert is_binary(mod.title()) and mod.title() != ""
        assert is_binary(mod.summary()) and mod.summary() != ""
        assert is_atom(mod.category())
        assert mod.category() in Guide.categories()
        assert is_list(mod.audience())
        assert mod.audience() != []
        assert Enum.all?(mod.audience(), &(&1 in [:admin, :volunteer]))
      end
    end

    test "every guide's faq entries are non-empty question/answer string pairs" do
      for mod <- @guides do
        faq = mod.faq()
        assert is_list(faq)

        for {question, answer} <- faq do
          assert is_binary(question) and question != ""
          assert is_binary(answer) and answer != ""
        end
      end
    end

    test "every guide's troubleshooting entries are non-empty strings" do
      for mod <- @guides do
        items = mod.troubleshooting()
        assert is_list(items)
        assert Enum.all?(items, &(is_binary(&1) and &1 != ""))
      end
    end

    test "every guide's steps have a title and body, and well-formed optional fields" do
      for mod <- @guides do
        steps = mod.steps()
        assert is_list(steps)
        assert steps != []

        for step <- steps do
          assert is_binary(step.title) and step.title != ""
          assert is_binary(step.body) and step.body != ""

          if cta = Map.get(step, :cta) do
            assert is_binary(cta.label) and cta.label != ""
            assert is_binary(cta.path) and cta.path != ""
          end

          if hotspots = Map.get(step, :hotspots) do
            assert is_list(hotspots)

            for hotspot <- hotspots do
              assert is_map(hotspot)
            end
          end
        end
      end
    end
  end

  describe "guide_context_for_llm/1 (via Registry, exercises faq/troubleshooting text rendering)" do
    test "renders a non-empty context block for every guide" do
      for mod <- @guides do
        context = Registry.guide_context_for_llm(mod)

        assert is_binary(context)
        assert context =~ mod.title()
        assert context =~ mod.summary()
      end
    end
  end
end
