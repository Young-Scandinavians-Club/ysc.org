defmodule YscWeb.Validators.FileValidator do
  @moduledoc """
  Validates file uploads by checking MIME types using magic number detection.

  This module provides security by validating the actual file content rather than
  relying solely on file extensions, which can be easily spoofed.
  """

  alias FileType

  # Dangerous MIME types detected via magic bytes (layer 1)
  @blocked_mimes MapSet.new([
                   "application/x-msdownload",
                   "application/x-msdos-program",
                   "application/x-executable",
                   "application/x-elf",
                   "application/x-mach-binary",
                   "application/x-sharedlib",
                   "application/java-archive",
                   "application/java-vm",
                   "application/vnd.microsoft.portable-executable",
                   "application/x-dosexec",
                   "application/x-sh",
                   "application/x-csh"
                 ])

  # Dangerous extensions checked against the client-provided filename (layer 2 + 3)
  @blocked_extensions MapSet.new([
                        # Executables / installers
                        ".exe",
                        ".bat",
                        ".cmd",
                        ".com",
                        ".scr",
                        ".pif",
                        ".msi",
                        ".msp",
                        ".mst",
                        ".cpl",
                        ".hta",
                        ".inf",
                        ".ins",
                        ".isp",
                        ".lnk",
                        ".reg",
                        ".rgs",
                        ".sct",
                        ".shb",
                        ".shs",
                        ".ws",
                        ".wsc",
                        ".wsf",
                        ".wsh",
                        # Scripts
                        ".ps1",
                        ".psm1",
                        ".psd1",
                        ".vbs",
                        ".vbe",
                        ".jse",
                        # System / library
                        ".sys",
                        ".dll",
                        ".drv",
                        ".ocx",
                        # Java
                        ".jar",
                        ".class",
                        ".jnlp",
                        # Shell
                        ".sh",
                        ".bash",
                        ".csh",
                        ".ksh",
                        ".zsh",
                        # Macro-enabled Office
                        ".docm",
                        ".xlsm",
                        ".pptm",
                        ".dotm",
                        ".xltm",
                        ".potm",
                        # macOS / Linux app bundles and launchers
                        ".app",
                        ".action",
                        ".command",
                        ".workflow",
                        ".desktop"
                      ])

  @doc """
  Detects the MIME type of a file via magic number detection.

  ## Returns
  - `{:ok, {ext, mime}}` if the file type is recognized
  - `{:ok, :unknown}` if the type cannot be determined (many legitimate plain-text types)
  - `{:error, reason}` if the file cannot be opened
  """
  # sobelow_skip ["Traversal.FileModule"]
  def detect_mime(file_path) do
    case File.open(file_path, [:read, :binary]) do
      {:ok, file} ->
        result =
          case FileType.from_io(file) do
            {:ok, {ext, mime}} ->
              {:ok, {ext, mime}}

            # Both :unknown and :unrecognized mean the library could not identify the magic bytes.
            # Treat as unknown type — extension checks still apply.
            {:error, :unknown} ->
              {:ok, :unknown}

            {:error, :unrecognized} ->
              {:ok, :unknown}

            {:error, reason} ->
              {:error, "Failed to detect file type: #{inspect(reason)}"}
          end

        File.close(file)
        result

      {:error, reason} when is_atom(reason) ->
        {:error, "Cannot open file: #{reason}"}
    end
  end

  @doc """
  Returns true if the file at the given path is an image, based on magic number detection.

  Returns false for any file whose magic bytes cannot be identified as an image,
  including files the `FileType` library does not recognise.
  """
  def image?(file_path) do
    case detect_mime(file_path) do
      {:ok, {_ext, mime}} -> String.starts_with?(mime, "image/")
      _ -> false
    end
  end

  @doc """
  Validates a non-image file attachment for editor uploads.

  Runs a layered security check:
  1. Null-byte / path-traversal defence on the client filename
  2. Blocked MIME types via magic number detection
  3. Blocked extensions (final and all intermediate extensions) from the client filename

  ## Parameters
  - `file_path`: Path to the temp file on disk
  - `client_filename`: The original filename provided by the browser

  ## Returns
  - `{:ok, mime}` where `mime` is the detected MIME or `"application/octet-stream"` if unknown
  - `{:error, reason}` if the file is blocked
  """
  def validate_attachment(file_path, client_filename) do
    with :ok <- check_filename_safety(client_filename),
         {:ok, mime_result} <- detect_mime(file_path),
         :ok <- check_blocked_mime(mime_result),
         :ok <- check_all_extensions(client_filename) do
      detected_mime =
        case mime_result do
          {_ext, mime} -> mime
          :unknown -> "application/octet-stream"
        end

      {:ok, detected_mime}
    end
  end

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
      {:error, reason} when is_atom(reason) ->
        {:error, reason}
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

  # --- Private helpers ---

  defp check_filename_safety(filename) do
    cond do
      String.contains?(filename, <<0>>) ->
        {:error, "Invalid filename"}

      String.contains?(filename, "../") or String.contains?(filename, "..\\") ->
        {:error, "Invalid filename"}

      true ->
        :ok
    end
  end

  defp check_blocked_mime(:unknown), do: :ok

  defp check_blocked_mime({_ext, mime}) do
    if MapSet.member?(@blocked_mimes, mime) do
      {:error, "File type not allowed"}
    else
      :ok
    end
  end

  # Checks the final extension AND all intermediate extensions (double-extension attack defence).
  # e.g. "report.exe.pdf" has intermediate ".exe" which is blocked.
  defp check_all_extensions(filename) do
    all_extensions =
      filename
      |> String.downcase()
      |> Path.basename()
      |> String.split(".")
      |> Enum.drop(1)
      |> Enum.map(&".#{&1}")

    case Enum.find(all_extensions, &MapSet.member?(@blocked_extensions, &1)) do
      nil -> :ok
      _ext -> {:error, "File type not allowed"}
    end
  end

  defp validate_file_type(file, allowed_mime_types, allowed_extensions) do
    case FileType.from_io(file) do
      {:ok, {detected_ext, detected_mime}} ->
        with :ok <- validate_mime_type(detected_mime, allowed_mime_types),
             :ok <- validate_extension(detected_ext, allowed_extensions) do
          {:ok, detected_mime}
        end

      {:error, reason} when reason in [:unknown, :unrecognized] ->
        {:error,
         "Could not detect file type. File may be corrupted or in an unsupported format."}

      {:error, reason} ->
        {:error, "Failed to detect file type: #{inspect(reason)}"}
    end
  end

  defp validate_mime_type(detected_mime, allowed_mime_types) do
    if detected_mime in allowed_mime_types do
      :ok
    else
      {:error,
       "File type #{detected_mime} not allowed. Allowed types: #{Enum.join(allowed_mime_types, ", ")}"}
    end
  end

  defp validate_extension(_detected_ext, []) do
    :ok
  end

  defp validate_extension(detected_ext, allowed_extensions) do
    ext_with_dot = ".#{detected_ext}"

    if ext_with_dot in allowed_extensions or detected_ext in allowed_extensions do
      :ok
    else
      {:error,
       "File extension .#{detected_ext} not allowed. Allowed extensions: #{Enum.join(allowed_extensions, ", ")}"}
    end
  end
end
