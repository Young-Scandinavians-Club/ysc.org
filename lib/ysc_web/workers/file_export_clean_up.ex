defmodule YscWeb.Workers.FileExportCleanUp do
  @moduledoc """
  Oban worker for cleaning up old export files.

  Removes export files that are older than a specified retention period.
  """
  require Logger
  use Oban.Worker, queue: :default, max_attempts: 1

  @spec perform(any()) :: :ok
  def perform(_) do
    Logger.info("Running export directory cleanup")
    directory = "#{:code.priv_dir(:ysc)}/static/exports"
    Logger.info(directory)

    files =
      File.ls!(directory)
      |> Enum.filter(fn f -> String.contains?(f, "ysc-user-export-") end)
      |> Enum.map(
        &{Path.join(directory, &1), File.stat!(Path.join(directory, &1)).ctime}
      )

    files_with_create_date =
      Enum.map(files, fn {f, ctime} ->
        {f, ctime_to_datetime(ctime)}
      end)

    deleted_files =
      Enum.reduce(files_with_create_date, 0, fn {f, creation_date}, acc ->
        acc + maybe_delete_file(f, creation_date)
      end)

    Logger.info("Cleaned up #{deleted_files} files")

    :ok
  end

  # sobelow_skip ["Traversal.FileModule"]
  def maybe_delete_file(f, create_date) do
    if Timex.before?(create_date, Timex.shift(Timex.now(), hours: -1)) do
      Logger.info("Deleting #{f}")

      case File.rm(f) do
        :ok ->
          1

        {:error, reason} ->
          Logger.warning("Error occured: #{reason}")
          0
      end
    else
      0
    end
  end

  def zero_pad(n) when n < 10, do: "0#{n}"
  def zero_pad(n), do: "#{n}"

  def ctime_to_datetime({{year, month, day}, {hour, minute, second}}) do
    naive_dt =
      NaiveDateTime.new!(year, month, day, hour, minute, second, {0, 0})

    DateTime.from_naive!(naive_dt, "Etc/UTC")
  end
end
