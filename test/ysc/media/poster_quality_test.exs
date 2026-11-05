defmodule Ysc.Media.PosterQualityTest do
  use ExUnit.Case, async: true

  alias Ysc.Media.Image
  alias Ysc.Media.PosterQuality

  describe "check/2" do
    test "accepts the recommended 1920×1080 size" do
      assert PosterQuality.check(1920, 1080) == []
    end

    test "accepts other 16:9 sizes at or above the minimum" do
      assert PosterQuality.check(1280, 720) == []
      assert PosterQuality.check(3840, 2160) == []
    end

    test "tolerates exports that are a few pixels off 16:9" do
      assert PosterQuality.check(1920, 1081) == []
      assert PosterQuality.check(1920, 1070) == []
    end

    test "the 2% tolerance is inclusive and exact at the boundary" do
      # 4080×2250 is exactly 2% off 16:9; float division would reject it.
      assert PosterQuality.check(4080, 2250) == []
      assert [{:aspect_ratio, _}] = PosterQuality.check(4081, 2250)
      assert PosterQuality.check(3920, 2250) == []
      assert [{:aspect_ratio, _}] = PosterQuality.check(3919, 2250)
    end

    test "flags 4:3, 3:2, square and portrait images as not 16:9" do
      for {w, h} <- [{2000, 1500}, {3000, 2000}, {2000, 2000}, {1080, 1920}] do
        assert {:aspect_ratio, %{width: w, height: h}} in PosterQuality.check(
                 w,
                 h
               )
      end
    end

    test "flags 16:10, which the event hero crops" do
      assert [{:aspect_ratio, _}] = PosterQuality.check(1920, 1200)
    end

    test "flags images below the minimum resolution" do
      assert [{:low_resolution, %{width: 640, height: 360}}] =
               PosterQuality.check(640, 360)
    end

    test "flags both problems together, aspect ratio first" do
      assert [{:aspect_ratio, _}, {:low_resolution, _}] =
               PosterQuality.check(640, 480)
    end

    test "a 16:9 image just under the minimum width is low resolution only" do
      assert PosterQuality.check(1200, 675) == [
               {:low_resolution, %{width: 1200, height: 675}}
             ]
    end
  end

  describe "assess/1" do
    test "measures an image with stored dimensions" do
      assert {:measured, []} =
               PosterQuality.assess(%Image{width: 1920, height: 1080})

      assert {:measured, [{:aspect_ratio, _}, {:low_resolution, _}]} =
               PosterQuality.assess(%Image{width: 800, height: 600})
    end

    test "says nothing about images without dimensions or without an image" do
      assert PosterQuality.assess(%Image{width: nil, height: nil}) ==
               :unmeasured

      assert PosterQuality.assess(%Image{width: 0, height: 0}) == :unmeasured
      assert PosterQuality.assess(nil) == :unmeasured
    end
  end

  describe "describe/1" do
    test "explains an aspect ratio problem with the actual size" do
      {title, detail} =
        PosterQuality.describe({:aspect_ratio, %{width: 2000, height: 1500}})

      assert title == "Not 16:9"
      assert detail =~ "2000×1500"
      assert detail =~ "1.33:1"
      assert detail =~ "1920×1080"
    end

    test "explains a resolution problem with the minimum" do
      {title, detail} =
        PosterQuality.describe({:low_resolution, %{width: 640, height: 360}})

      assert title == "Low resolution"
      assert detail =~ "640×360"
      assert detail =~ "1280×720"
    end
  end
end
