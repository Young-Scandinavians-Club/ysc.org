defmodule YscWeb.UploadErrors do
  @moduledoc """
  Human-readable messages for Phoenix LiveView upload validation errors.

  Use `error_to_string/2` with a `:variant` for context-specific copy
  (avatar limits, expense receipts, event photo batches, etc.).
  """

  @type variant :: :default | :admin | :avatar | :expense | :event_photo

  @variants [:default, :admin, :avatar, :expense, :event_photo]

  @doc """
  Converts a LiveView upload error atom (or tuple) to a user-facing string.

  ## Variants

  - `:default` — generic image upload forms
  - `:admin` — admin media uploads; includes S3/external failure copy
  - `:avatar` — profile photo upload on account settings
  - `:expense` — expense report receipt and proof uploads
  - `:event_photo` — event photo and video batch upload
  """
  @spec error_to_string(term(), keyword() | variant()) :: String.t()
  def error_to_string(error, opts \\ [])

  def error_to_string(error, variant) when variant in @variants do
    error_to_string(error, variant: variant)
  end

  def error_to_string(:too_large, opts) do
    case Keyword.get(opts, :variant, :default) do
      :avatar -> "Image must be under 10 MB"
      :expense -> "File is too large (max 10MB)"
      :event_photo -> "File is too large (photos max 200 MB, videos max 20 GB)"
      _ -> "Too large"
    end
  end

  def error_to_string(:not_accepted, opts) do
    case Keyword.get(opts, :variant, :default) do
      :avatar ->
        "Only JPG, PNG, WebP, and GIF files are accepted"

      :expense ->
        "Invalid file type. Use PDF, JPG, JPEG, PNG, or WEBP"

      :event_photo ->
        "File type not accepted — use a photo or video format we support"

      _ ->
        "You have selected an unacceptable file type"
    end
  end

  def error_to_string(:too_many_files, opts) do
    case Keyword.get(opts, :variant, :default) do
      :avatar ->
        "Only one photo at a time"

      :expense ->
        "Too many files selected"

      :event_photo ->
        "You can upload up to 30 files per batch. Submit these first, then use Upload more to add another batch."

      _ ->
        "You have selected too many files"
    end
  end

  def error_to_string(:external_client_failure, _opts) do
    "Upload failed: The file could not be uploaded to storage. " <>
      "This may be due to network issues, CORS configuration, or invalid credentials. " <>
      "Please check the browser console for more details."
  end

  def error_to_string(_error, opts) do
    case Keyword.get(opts, :variant, :default) do
      :avatar ->
        "Upload failed"

      :admin ->
        "An error occurred"

      :expense ->
        "Something went wrong uploading that file. Please try again, or use a different file format."

      :event_photo ->
        "Something went wrong uploading that file. Please try again, or use a different photo or video format."

      _ ->
        "An error occurred"
    end
  end
end
