defmodule YscWeb.Validators.FileValidator do
  @moduledoc """
  Validates file uploads by checking MIME types using magic number detection.

  This module provides security by validating the actual file content rather than
  relying solely on file extensions, which can be easily spoofed.
  """

  alias FileType

  @doc """
  Validates that a file's MIME type matches the allowed types.

  ## Parameters
  - `file_path`: Path to the file to validate
  - `allowed_mime_types`: List of allowed MIME types (e.g., ["image/jpeg", "image/png"])
  - `allowed_extensions`: Optional list of allowed extensions (e.g., [".jpg", ".png"])

  ## Returns
  - `{:ok, detected_mime_type}` if the file is valid
  - `{:error, reason}` if the file is invalid or cannot be read

  ## Examples
      iex> validate_file("/tmp/upload.jpg", ["image/jpeg", "image/png"], [".jpg", ".jpeg", ".png"])
      {:ok, "image/jpeg"}
      
      iex> validate_file("/tmp/malicious.exe", ["image/jpeg"], [".jpg"])
      {:error, "File type application/x-msdownload not allowed. Allowed types: image/jpeg"}
  """
  # sobelow_skip ["Traversal.FileModule"]
  def validate_file(file_path, allowed_mime_types, allowed_extensions \\ []) do
    with {:ok, file} <- File.open(file_path, [:read, :binary]),
         result <-
           validate_file_type(file, allowed_mime_types, allowed_extensions),
         :ok <- File.close(file) do
      result
    else
      {:error, reason} = error when is_atom(reason) ->
        error

      {:error, reason} ->
        {:error, "Failed to validate file: #{inspect(reason)}"}

      other ->
        {:error, "Unexpected error validating file: #{inspect(other)}"}
    end
  end

  defp validate_file_type(file, allowed_mime_types, allowed_extensions) do
    case FileType.from_io(file) do
      {:ok, {detected_ext, detected_mime}} ->
        with :ok <- validate_mime_type(detected_mime, allowed_mime_types),
             :ok <- validate_extension(detected_ext, allowed_extensions) do
          {:ok, detected_mime}
        end

      {:error, :unknown} ->
        {:error,
         "Could not detect file type. File may be corrupted or in an unsupported format."}

      {:error, reason} ->
        {:error, "Failed to detect file type: #{inspect(reason)}"}
    end
  end

  @doc """
  Validates an image file specifically.

  Convenience function for validating image uploads.

  ## Parameters
  - `file_path`: Path to the file to validate
  - `allowed_extensions`: Optional list of allowed extensions

  ## Returns
  - `{:ok, detected_mime_type}` if the file is a valid image
  - `{:error, reason}` if the file is invalid

  ## Examples
      iex> validate_image("/tmp/photo.jpg", [".jpg", ".png"])
      {:ok, "image/jpeg"}
  """
  def validate_image(file_path, allowed_extensions \\ []) do
    allowed_mime_types = [
      "image/jpeg",
      "image/png",
      "image/gif",
      "image/webp",
      "image/svg+xml"
    ]

    validate_file(file_path, allowed_mime_types, allowed_extensions)
  end

  @doc """
  Validates a document file (PDF or images for receipts/proofs).

  Convenience function for validating document uploads like expense receipts.

  ## Parameters
  - `file_path`: Path to the file to validate
  - `allowed_extensions`: Optional list of allowed extensions

  ## Returns
  - `{:ok, detected_mime_type}` if the file is a valid document
  - `{:error, reason}` if the file is invalid
  """
  def validate_document(file_path, allowed_extensions \\ []) do
    allowed_mime_types = [
      "application/pdf",
      "image/jpeg",
      "image/png",
      "image/webp"
    ]

    validate_file(file_path, allowed_mime_types, allowed_extensions)
  end

  # Private helper functions

  defp validate_mime_type(detected_mime, allowed_mime_types) do
    if detected_mime in allowed_mime_types do
      :ok
    else
      {:error,
       "File type #{detected_mime} not allowed. Allowed types: #{Enum.join(allowed_mime_types, ", ")}"}
    end
  end

  defp validate_extension(_detected_ext, []) do
    # No extension validation required
    :ok
  end

  defp validate_extension(detected_ext, allowed_extensions) do
    # FileType returns extension without dot, so we need to add it for comparison
    ext_with_dot = ".#{detected_ext}"

    if ext_with_dot in allowed_extensions or detected_ext in allowed_extensions do
      :ok
    else
      {:error,
       "File extension .#{detected_ext} not allowed. Allowed extensions: #{Enum.join(allowed_extensions, ", ")}"}
    end
  end
end
