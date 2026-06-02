defmodule YscWeb.AdminExportFiles do
  @moduledoc false

  alias YscWeb.SafeSendFile

  @export_filename_regex ~r/^ysc-user-export-(\d{4}-\d{2}-\d{2})-([0-9A-HJKMNP-TV-Z]{26})-([0-9A-HJKMNP-TV-Z]{26})\.csv$/u

  @export_unavailable "Export file is no longer available. Please run the export again."

  @spec exports_root() :: String.t()
  def exports_root do
    Path.join([:code.priv_dir(:ysc), "static", "exports"])
  end

  @spec valid_filename?(String.t()) :: boolean()
  def valid_filename?(filename) when is_binary(filename) do
    Regex.match?(@export_filename_regex, filename)
  end

  def valid_filename?(_), do: false

  @spec export_owner_id(String.t()) :: String.t() | nil
  def export_owner_id(filename) do
    case Regex.run(@export_filename_regex, filename) do
      [_full, _date, owner_id, _file_ulid] -> owner_id
      _ -> nil
    end
  end

  @spec owned_by_user?(String.t(), map()) :: boolean()
  def owned_by_user?(filename, user) when is_binary(filename) do
    case export_owner_id(filename) do
      owner_id when is_binary(owner_id) -> ulid_match?(owner_id, user.id)
      _ -> false
    end
  end

  def owned_by_user?(_, _), do: false

  @spec filename_from_path(String.t()) :: String.t() | nil
  def filename_from_path(path) when is_binary(path) do
    path
    |> String.replace_prefix("/admin/exports/", "")
    |> Path.basename()
    |> case do
      "" -> nil
      name -> name
    end
  end

  @spec read(String.t()) ::
          {:ok, binary(), String.t()} | {:error, :invalid | :missing}
  def read(filename) when is_binary(filename) do
    with true <- valid_filename?(filename),
         {:ok, content} <- SafeSendFile.read_within(exports_root(), filename) do
      {:ok, content, filename}
    else
      false -> {:error, :invalid}
      :error -> {:error, :missing}
    end
  end

  @spec read_for_user(String.t(), map()) ::
          {:ok, binary(), String.t()}
          | {:error, :invalid | :missing | :forbidden}
  def read_for_user(filename, user) when is_binary(filename) do
    owner_id = export_owner_id(filename)

    with true <- valid_filename?(filename),
         true <- is_binary(owner_id),
         true <- ulid_match?(owner_id, user.id),
         {:ok, content, ^filename} <- read(filename) do
      {:ok, content, filename}
    else
      {:error, reason} when reason in [:invalid, :missing] -> {:error, reason}
      _ -> {:error, :forbidden}
    end
  end

  @spec read_from_path(String.t(), map()) ::
          {:ok, binary(), String.t()} | {:error, String.t()}
  def read_from_path(path, user) when is_binary(path) do
    case filename_from_path(path) do
      nil ->
        {:error, @export_unavailable}

      filename ->
        case read_for_user(filename, user) do
          {:ok, content, name} -> {:ok, content, name}
          {:error, _} -> {:error, @export_unavailable}
        end
    end
  end

  defp ulid_match?(left, right) do
    normalize_ulid(left) == normalize_ulid(right)
  end

  defp normalize_ulid(id) when is_binary(id), do: String.upcase(id)
  defp normalize_ulid(id), do: id |> to_string() |> String.upcase()
end
