defmodule YscWeb.Workers.ImageReprocessor do
  @moduledoc """
  Oban worker for reprocessing unprocessed or stuck images.

  Runs once per night to find all images that are still in :unprocessed or :processing
  state and attempts to process them. This helps recover from failed processing jobs
  or images that were uploaded but never processed.
  """

  require Logger

  use Oban.Worker, queue: :media, max_attempts: 1

  alias Ysc.Media

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    Logger.info("Starting image reprocessor job", job_id: job.id)

    # Find all images that need processing
    images = Media.list_unprocessed_images()

    Logger.info("Found #{length(images)} images to reprocess", job_id: job.id)

    # Process each image by enqueueing individual ImageProcessor jobs
    results =
      Enum.map(images, fn image ->
        Logger.info("Enqueueing reprocessing for image: #{image.id}",
          job_id: job.id
        )

        case enqueue_image_processing(image) do
          {:ok, _job} ->
            {:ok, image.id}

          {:error, reason} ->
            Logger.error(
              "Failed to enqueue image #{image.id}: #{inspect(reason)}",
              job_id: job.id
            )

            {:error, image.id, reason}
        end
      end)

    successful = Enum.count(results, fn r -> match?({:ok, _}, r) end)
    failed = Enum.count(results, fn r -> match?({:error, _, _}, r) end)

    Logger.info(
      "Image reprocessor job completed. Successful: #{successful}, Failed: #{failed}",
      job_id: job.id
    )

    :ok
  end

  @impl Oban.Worker
  def timeout(_job) do
    # Job timeout after 30 minutes (should be plenty for enqueueing jobs)
    30 * 60 * 1000
  end

  # Enqueue an individual image for processing
  defp enqueue_image_processing(image) do
    %{"id" => image.id}
    |> YscWeb.Workers.ImageProcessor.new()
    |> Oban.insert()
  end
end
