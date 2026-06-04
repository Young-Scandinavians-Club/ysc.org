defmodule Ysc.Coveralls do
  @moduledoc false

  @doc """
  ExCoveralls-compatible coverage entrypoint with clearer failures when
  Erlang `:cover` cannot instrument stale or incompatible BEAM files.
  """
  def start(compile_path, opts) do
    compile!(compile_path)

    fn ->
      options = ExCoveralls.ConfServer.get()

      if options[:import_cover] do
        ExCoveralls.Cover.import(options[:import_cover])
      end

      ExCoveralls.execute(options, compile_path, opts)
    end
  end

  defp compile!(compile_path) do
    :cover.stop()
    {:ok, pid} = :cover.start()

    {:ok, string_io} = StringIO.open("")
    Process.group_leader(pid, string_io)

    failures =
      compile_path
      |> Path.join("*.beam")
      |> Path.wildcard()
      |> Enum.flat_map(fn beam ->
        case :cover.compile_beam(String.to_charlist(beam)) do
          {:ok, _module} ->
            []

          error ->
            [{beam, error}]
        end
      end)

    if failures == [] do
      :ok
    else
      raise cover_failure_message(failures)
    end
  end

  defp cover_failure_message(failures) do
    modules =
      failures
      |> Enum.map_join("\n", fn {beam, error} -> "  #{beam}: #{inspect(error)}" end)

    """
    cover instrumentation failed for #{length(failures)} module(s).

    This usually means `_build` contains BEAM files compiled with a different
    Elixir/OTP version. Clean and recompile, then retry:

      mix clean
      mix deps.compile --force
      mix compile

    Failed modules:
    #{modules}
    """
  end
end
