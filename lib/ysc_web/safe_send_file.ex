defmodule YscWeb.SafeSendFile do
  @moduledoc false

  import Plug.Conn

  @doc """
  Sends a regular file at `relative_path` when it resolves inside `root`.

  Returns `{:ok, conn}` or `:error`.

  Use the `:prepare` option to set response headers after the file is validated
  but before it is sent.
  """
  @spec send_within(
          Plug.Conn.t(),
          non_neg_integer(),
          String.t(),
          String.t(),
          keyword()
        ) ::
          {:ok, Plug.Conn.t()} | :error
  def send_within(conn, status, root, relative_path, opts \\ [])
      when is_integer(status) and is_binary(root) and is_binary(relative_path) do
    prepare = Keyword.get(opts, :prepare, fn conn, _absolute_path -> conn end)

    case resolve_regular_file(root, relative_path) do
      {:ok, absolute_path} ->
        {:ok,
         do_send_file(prepare.(conn, absolute_path), status, absolute_path)}

      :error ->
        :error
    end
  end

  @doc """
  Reads a regular file at `relative_path` when it resolves inside `root`.

  Returns `{:ok, binary}` or `:error`.
  """
  @spec read_within(String.t(), String.t()) :: {:ok, binary()} | :error
  def read_within(root, relative_path)
      when is_binary(root) and is_binary(relative_path) do
    case resolve_regular_file(root, relative_path) do
      {:ok, absolute_path} -> {:ok, do_read_file!(absolute_path)}
      :error -> :error
    end
  end

  defp resolve_regular_file(root, relative_path) do
    expanded_root = Path.expand(root)

    with {:ok, safe_relative} <-
           Path.safe_relative(relative_path, expanded_root),
         absolute_path = Path.join(expanded_root, safe_relative),
         true <- File.regular?(absolute_path) do
      {:ok, absolute_path}
    else
      _ -> :error
    end
  end

  # Path is validated with Path.safe_relative/2 in resolve_regular_file/2.
  # sobelow_skip ["Traversal.FileModule"]
  defp do_read_file!(absolute_path), do: File.read!(absolute_path)

  # Paths are validated with Path.safe_relative/2 before send_file is invoked.
  # sobelow_skip ["Traversal.SendFile"]
  defp do_send_file(conn, status, absolute_path) do
    conn =
      case get_resp_header(conn, "content-type") do
        [] -> put_content_type_for_extension(conn, absolute_path)
        _ -> conn
      end

    send_file(conn, status, absolute_path)
  end

  defp put_content_type_for_extension(conn, absolute_path) do
    case String.downcase(Path.extname(absolute_path)) do
      ".csv" ->
        put_resp_content_type(conn, "text/csv")

      ".pdf" ->
        put_resp_content_type(conn, "application/pdf")

      ".docx" ->
        put_resp_content_type(
          conn,
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        )

      ".pptx" ->
        put_resp_content_type(
          conn,
          "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        )

      _ ->
        put_resp_content_type(conn, "application/octet-stream")
    end
  end
end
