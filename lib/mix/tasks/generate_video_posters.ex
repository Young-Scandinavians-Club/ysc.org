defmodule Mix.Tasks.GenerateVideoPosters do
  @moduledoc """
  Generates poster images from hero videos at build time.

  Extracts a frame from each video file and saves it as a JPG poster image.
  Uses ffmpeg to extract a frame at 1 second into the video.

  ## Usage

      mix generate_video_posters

  This task should be run as part of the assets build process.
  """
  use Mix.Task

  @shortdoc "Generates poster images from hero videos"

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("Generating video poster images...")

    video_configs = [
      {
        "priv/static/video/tahoe_hero.mp4",
        "priv/static/images/tahoe_hero_poster.jpg"
      },
      {
        "priv/static/video/clear_lake_hero.mp4",
        "priv/static/images/clear_lake_hero_poster.jpg"
      }
    ]

    results =
      Enum.map(video_configs, fn {video_path, poster_path} ->
        generate_poster(video_path, poster_path)
      end)

    successful = Enum.count(results, &(&1 == :ok))
    total = length(results)

    if successful == total do
      Mix.shell().info(
        "✅ Successfully generated #{successful}/#{total} poster images"
      )
    else
      failed = total - successful

      Mix.shell().error(
        "⚠️  Generated #{successful}/#{total} poster images (#{failed} failed)"
      )

      System.halt(1)
    end
  end

  defp generate_poster(video_path, poster_path) do
    if File.exists?(video_path) do
      # Ensure output directory exists
      poster_dir = Path.dirname(poster_path)
      File.mkdir_p!(poster_dir)

      # Extract frame at 1 second (or first frame if video is shorter)
      # Using -ss before -i is faster as it seeks before decoding
      # -vframes 1 extracts only one frame
      # -q:v 2 sets high quality (lower number = higher quality, range 1-31)
      # Start with simpler command, add scaling if needed
      cmd = [
        # Overwrite output file
        "-y",
        # Seek to 1 second
        "-ss",
        "1",
        "-i",
        video_path,
        # Extract only one frame
        "-vframes",
        "1",
        # High quality JPEG
        "-q:v",
        "2",
        poster_path
      ]

      # Run ffmpeg - it outputs to stderr by default, so we capture both
      case System.cmd("ffmpeg", cmd, stderr_to_stdout: true) do
        {_output, 0} ->
          Mix.shell().info("  ✓ Generated #{poster_path}")
          :ok

        {output, exit_code} ->
          Mix.shell().error("  ✗ Failed to generate #{poster_path}")
          Mix.shell().error("    Exit code: #{exit_code}")

          # Extract error messages from ffmpeg output
          error_lines =
            output
            |> String.split("\n")
            |> Enum.filter(fn line ->
              line != "" &&
                (String.contains?(String.downcase(line), "error") ||
                   String.contains?(String.downcase(line), "failed") ||
                   String.contains?(String.downcase(line), "invalid") ||
                   String.contains?(String.downcase(line), "no such file"))
            end)

          if error_lines != [] do
            Mix.shell().error("    Error details:")

            Enum.each(error_lines, fn line ->
              Mix.shell().error("      #{line}")
            end)
          else
            # Show last few lines if no specific error found
            last_lines =
              output
              |> String.split("\n")
              |> Enum.filter(&(&1 != ""))
              |> Enum.take(-5)

            if last_lines != [] do
              Mix.shell().error("    Last output lines:")

              Enum.each(last_lines, fn line ->
                Mix.shell().error("      #{line}")
              end)
            end
          end

          :error
      end
    else
      Mix.shell().warn("  ⚠ Video file not found: #{video_path}")
      :error
    end
  end
end
