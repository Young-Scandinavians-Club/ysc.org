defmodule Ysc.MemberDocuments do
  @moduledoc """
  Resolves member-only document paths under `priv/static/annual_meetings`.
  """

  @annual_meetings_root Path.join([
                          :code.priv_dir(:ysc),
                          "static",
                          "annual_meetings"
                        ])

  @doc """
  Returns the absolute filesystem path for a relative annual meeting document,
  or `:error` when the path is invalid or the file does not exist.
  """
  @spec annual_meeting_path(String.t()) :: {:ok, String.t()} | :error
  def annual_meeting_path(relative_path) when is_binary(relative_path) do
    with :ok <- validate_annual_meeting_relative_path(relative_path),
         absolute = Path.join(@annual_meetings_root, relative_path),
         true <- File.regular?(absolute),
         true <- path_within_root?(absolute) do
      {:ok, absolute}
    else
      _ -> :error
    end
  end

  def annual_meeting_path(_), do: :error

  @doc false
  def validate_annual_meeting_relative_path(path) when is_binary(path) do
    cond do
      path == "" ->
        :error

      String.contains?(path, "..") ->
        :error

      not String.match?(path, ~r/^\d{4}\/[^\/]+$/) ->
        :error

      true ->
        :ok
    end
  end

  defp path_within_root?(absolute_path) do
    expanded = Path.expand(absolute_path)
    root = Path.expand(@annual_meetings_root)
    String.starts_with?(expanded, root <> "/") or expanded == root
  end
end
