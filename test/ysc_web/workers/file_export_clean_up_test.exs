defmodule YscWeb.Workers.FileExportCleanUpTest do
  use ExUnit.Case, async: true

  alias YscWeb.Workers.FileExportCleanUp

  describe "zero_pad/1" do
    test "pads single digit" do
      assert FileExportCleanUp.zero_pad(0) == "00"
      assert FileExportCleanUp.zero_pad(9) == "09"
    end

    test "does not pad double digit" do
      assert FileExportCleanUp.zero_pad(10) == "10"
    end
  end

  describe "ctime_to_datetime/1" do
    test "converts Erlang ctime to UTC DateTime" do
      dt = FileExportCleanUp.ctime_to_datetime({{2026, 1, 1}, {1, 2, 3}})
      assert dt.time_zone == "Etc/UTC"
      assert dt.year == 2026
      assert dt.month == 1
      assert dt.day == 1
      assert dt.hour == 1
      assert dt.minute == 2
      assert dt.second == 3
    end
  end

  describe "maybe_delete_file/2" do
    test "deletes file when older than 1 hour" do
      path =
        Path.join(
          System.tmp_dir!(),
          "ysc-export-#{System.unique_integer([:positive])}"
        )

      File.write!(path, "x")

      old = Timex.shift(Timex.now(), hours: -2)
      assert FileExportCleanUp.maybe_delete_file(path, old) == 1
      refute File.exists?(path)
    end

    test "does not delete recent file" do
      path =
        Path.join(
          System.tmp_dir!(),
          "ysc-export-#{System.unique_integer([:positive])}"
        )

      File.write!(path, "x")

      recent = Timex.shift(Timex.now(), minutes: -10)
      assert FileExportCleanUp.maybe_delete_file(path, recent) == 0
      assert File.exists?(path)
      File.rm!(path)
    end

    test "returns 0 when deletion fails" do
      # Non-existent file -> File.rm/1 returns {:error, :enoent}
      path =
        Path.join(
          System.tmp_dir!(),
          "missing-#{System.unique_integer([:positive])}"
        )

      old = Timex.shift(Timex.now(), hours: -2)
      assert FileExportCleanUp.maybe_delete_file(path, old) == 0
    end
  end
end
