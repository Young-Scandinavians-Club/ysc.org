defmodule YscWeb.CoreComponentsMotionTest do
  @moduledoc """
  The show/hide and modal helpers share one motion contract:

    * enter and exit have the same duration and mirrored start/end states, so
      appearing and disappearing are the same motion played both ways;
    * the JS op `time` is at least the CSS duration (LiveView strips the
      transition classes after `time`, so a shorter `time` cuts the animation
      off partway);
    * a modal's panel and backdrop share a duration so the layers never desync.
  """
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias YscWeb.CoreComponents

  # LiveView starts the CSS transition about two animation frames (~33ms) after
  # the op runs, but hides the element / strips the classes `time` after the op.
  # So `time` must beat the duration by at least that much or the tail is cut off.
  @frame_slack_ms 32

  # --- helpers ---------------------------------------------------------------

  defp op!(js, kind, to) do
    Enum.find_value(js.ops, fn
      [^kind, %{to: ^to} = args] -> args
      _ -> nil
    end) || flunk("no #{kind} op for #{to} in #{inspect(js.ops)}")
  end

  defp duration_ms(classes) do
    case Enum.find_value(
           List.flatten(classes),
           &Regex.run(~r/^duration-(\d+)$/, &1)
         ) do
      [_, ms] -> String.to_integer(ms)
      nil -> flunk("no duration-* class in #{inspect(classes)}")
    end
  end

  defp easing(classes),
    do: Enum.find(List.flatten(classes), &String.starts_with?(&1, "ease-"))

  # `transition: [running, start, end]`
  defp transition(%{transition: [running, start, finish]}),
    do: {running, start, finish}

  # --- generic show/hide -----------------------------------------------------

  describe "show/1 and hide/1" do
    test "enter and exit have the same duration" do
      {enter, _, _} =
        transition(op!(CoreComponents.show("#flash"), "show", "#flash"))

      {exit_, _, _} =
        transition(op!(CoreComponents.hide("#flash"), "hide", "#flash"))

      assert duration_ms(enter) == duration_ms(exit_)
    end

    test "enter decelerates and exit accelerates" do
      {enter, _, _} =
        transition(op!(CoreComponents.show("#flash"), "show", "#flash"))

      {exit_, _, _} =
        transition(op!(CoreComponents.hide("#flash"), "hide", "#flash"))

      assert easing(enter) == "ease-[cubic-bezier(0.32,0.72,0,1)]"

      # Not the strict time-reversal of the enter curve: that holds still and then
      # snaps, which reads as a delay followed by a hard cut.
      assert easing(exit_) == "ease-[cubic-bezier(0.32,0,0.67,0)]"
    end

    test "hide starts where show ends and ends where show starts" do
      {_, show_start, show_end} =
        transition(op!(CoreComponents.show("#flash"), "show", "#flash"))

      {_, hide_start, hide_end} =
        transition(op!(CoreComponents.hide("#flash"), "hide", "#flash"))

      assert hide_start == show_end
      assert hide_end == show_start
    end

    test "op time exceeds the CSS duration by LiveView's two-frame start delay" do
      show = op!(CoreComponents.show("#flash"), "show", "#flash")
      hide = op!(CoreComponents.hide("#flash"), "hide", "#flash")

      {show_run, _, _} = transition(show)
      {hide_run, _, _} = transition(hide)

      assert show.time >= duration_ms(show_run) + @frame_slack_ms
      assert hide.time >= duration_ms(hide_run) + @frame_slack_ms
    end
  end

  # --- modals ----------------------------------------------------------------

  describe "show_modal/1 and hide_modal/1" do
    setup do
      %{
        open: CoreComponents.show_modal("m"),
        close: CoreComponents.hide_modal("m")
      }
    end

    test "panel and backdrop share a duration, in and out", %{
      open: open,
      close: close
    } do
      for {js, kind} <- [{open, "show"}, {close, "hide"}] do
        {panel, _, _} = transition(op!(js, kind, "#m-container"))
        {backdrop, _, _} = transition(op!(js, kind, "#m-bg"))

        assert duration_ms(panel) == duration_ms(backdrop)
      end
    end

    test "enter and exit have the same duration", %{open: open, close: close} do
      {enter, _, _} = transition(op!(open, "show", "#m-container"))
      {exit_, _, _} = transition(op!(close, "hide", "#m-container"))

      assert duration_ms(enter) == duration_ms(exit_)
    end

    test "every transitioned op's time covers its CSS duration", %{
      open: open,
      close: close
    } do
      for {js, kind, to} <- [
            {open, "show", "#m-bg"},
            {open, "show", "#m-container"},
            {close, "hide", "#m-bg"},
            {close, "hide", "#m-container"}
          ] do
        args = op!(js, kind, to)
        {running, _, _} = transition(args)

        assert args.time >= duration_ms(running) + @frame_slack_ms,
               "#{kind} #{to} would be cut short"
      end
    end

    test "the root is not hidden before the panel finishes leaving", %{
      close: close
    } do
      {panel, _, _} = transition(op!(close, "hide", "#m-container"))
      root = op!(close, "hide", "#m")

      assert root.time >= duration_ms(panel) + @frame_slack_ms
    end

    test "opening announces itself so the panel can anchor to its trigger", %{
      open: open
    } do
      assert %{event: "ysc:modal-opening"} =
               op!(open, "dispatch", "#m-container")
    end

    test "closing announces itself so the panel can return to its trigger", %{
      close: close
    } do
      assert %{event: "ysc:modal-closing"} =
               op!(close, "dispatch", "#m-container")
    end
  end

  # --- dropdown origin -------------------------------------------------------

  describe "dropdown/1 transform origin" do
    defp render_dropdown(assigns) do
      assigns = Map.new(assigns)

      rendered_to_string(~H"""
      <CoreComponents.dropdown id="d" right={@right} drop_up={@drop_up}>
        <:button_block>Menu</:button_block>
        <a href="/x">Item</a>
      </CoreComponents.dropdown>
      """)
    end

    test "grows from the corner nearest its trigger" do
      assert render_dropdown(right: false, drop_up: false) =~ "origin-top-left"
      assert render_dropdown(right: true, drop_up: false) =~ "origin-top-right"

      assert render_dropdown(right: false, drop_up: true) =~
               "origin-bottom-left"

      assert render_dropdown(right: true, drop_up: true) =~
               "origin-bottom-right"
    end
  end
end
