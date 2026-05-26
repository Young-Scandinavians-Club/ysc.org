defmodule YscWeb.SafeSendFile do
  @moduledoc false

  import Plug.Conn

  @doc """
  Sends a regular file at `relative_path` when it resolves inside `root`.

  Returns `{:ok, conn}` or `:error`.
  """
  @spec send_within(Plug.Conn.t(), non_neg_integer(), String.t(), String.t()) ::
          {:ok, Plug.Conn.t()} | :error
  def send_within(conn, status, root, relative_path)
      when is_integer(status) and is_binary(root) and is_binary(relative_path) do
    expanded_root = Path.expand(root)

    with {:ok, safe_relative} <-
           Path.safe_relative(relative_path, expanded_root),
         absolute_path = Path.join(expanded_root, safe_relative),
         true <- File.regular?(absolute_path) do
      {:ok, do_send_file(conn, status, absolute_path)}
    else
      _ -> :error
    end
  end

  # Paths are validated with Path.safe_relative/2 before send_file is invoked.
  # sobelow_skip ["Traversal.SendFile"]
  defp do_send_file(conn, status, absolute_path) do
    send_file(conn, status, absolute_path)
  end
end
