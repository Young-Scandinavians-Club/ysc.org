defmodule QueryConsole.LotusWeb.HelpersPatch do
  @moduledoc false

  @patch_name "lotus_web_helpers_patch.ex"

  @doc """
  Replaces `Lotus.Web.Helpers` with a root-mount-safe path joiner.

  The patch source lives in `priv/` (included in releases) and is compiled at
  runtime so `mix release` does not see a duplicate module.
  """
  def install! do
    {:module, _} = Code.ensure_loaded(Lotus.Web.Helpers)

    :code.purge(Lotus.Web.Helpers)
    :code.delete(Lotus.Web.Helpers)

    path = patch_source_path!()

    Code.put_compiler_option(:ignore_module_conflict, true)
    Code.compile_file(path)
    Code.put_compiler_option(:ignore_module_conflict, false)

    unless function_exported?(Lotus.Web.Helpers, :__query_console_patched__, 0) do
      raise "Lotus.Web.Helpers patch failed to load from #{path}"
    end

    :ok
  end

  @doc """
  No-op when the patch is already active (e.g. after a soft reload).
  """
  def ensure! do
    if function_exported?(Lotus.Web.Helpers, :__query_console_patched__, 0) do
      :ok
    else
      install!()
    end
  end

  defp patch_source_path! do
    candidates = [
      Application.app_dir(:query_console, Path.join("priv", @patch_name)),
      Path.expand(Path.join(["priv", @patch_name]), File.cwd!())
    ]

    Enum.find(candidates, &File.exists?/1) ||
      raise """
      Lotus.Web.Helpers patch source not found. Tried:
      #{Enum.map_join(candidates, "\n", &("  - " <> &1))}
      """
  end
end
