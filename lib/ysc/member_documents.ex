defmodule Ysc.MemberDocuments do
  @moduledoc """
  Resolves member-only document paths under `priv/static/annual_meetings`.
  """

  @doc false
  def annual_meetings_root do
    # Resolve at runtime so Mix releases use the unpacked priv dir, not the
    # compile-time `_build/.../priv` path (which 404s in production).
    Path.join([:code.priv_dir(:ysc), "static", "annual_meetings"])
  end

  @doc """
  Returns the absolute filesystem path for a relative annual meeting document,
  or `:error` when the path is invalid or the file does not exist.
  """
  @spec annual_meeting_path(String.t()) :: {:ok, String.t()} | :error
  def annual_meeting_path(relative_path) when is_binary(relative_path) do
    expanded_root = Path.expand(annual_meetings_root())

    with :ok <- validate_annual_meeting_relative_path(relative_path),
         {:ok, safe_relative} <-
           Path.safe_relative(relative_path, expanded_root),
         absolute = Path.join(expanded_root, safe_relative),
         true <- File.regular?(absolute) do
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
end
