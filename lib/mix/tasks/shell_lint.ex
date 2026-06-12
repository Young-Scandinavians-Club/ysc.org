defmodule Mix.Tasks.ShellLint do
  @moduledoc """
  Runs ShellCheck and shfmt on shell scripts.

  Requires shellcheck and shfmt to be installed:
    - macOS: brew install shellcheck shfmt
    - Ubuntu: apt install shellcheck shfmt
  """
  use Mix.Task

  @shortdoc "Lint and check format of shell scripts"

  def run(_args) do
    scripts = find_shell_scripts()

    if scripts == [] do
      Mix.shell().info("No shell scripts found")
    else
      shellcheck_ok = run_shellcheck(scripts)
      shfmt_ok = run_shfmt_check(scripts)

      if not (shellcheck_ok and shfmt_ok) do
        System.halt(1)
      end
    end
  end

  defp find_shell_scripts do
    root = File.cwd!()

    Path.wildcard(Path.join(root, "**/*.sh"))
    |> Enum.reject(fn path ->
      String.contains?(path, "/_build/") or
        String.contains?(path, "/deps/") or
        String.contains?(path, "/node_modules/")
    end)
  end

  defp run_shellcheck(scripts) do
    case System.find_executable("shellcheck") do
      nil ->
        Mix.shell().error(
          "shellcheck not found. Install with: brew install shellcheck"
        )

        false

      _path ->
        {output, status} =
          System.cmd("shellcheck", scripts, stderr_to_stdout: true)

        IO.write(output)

        if status != 0 do
          Mix.shell().error("ShellCheck found issues")
          false
        else
          true
        end
    end
  end

  defp run_shfmt_check(scripts) do
    case System.find_executable("shfmt") do
      nil ->
        Mix.shell().error("shfmt not found. Install with: brew install shfmt")
        false

      _path ->
        {output, status} =
          System.cmd("shfmt", ["-d", "-i", "2", "-ci"] ++ scripts,
            stderr_to_stdout: true
          )

        IO.write(output)

        if status != 0 do
          Mix.shell().error(
            "shfmt found formatting issues. Run 'make format' to fix."
          )

          false
        else
          true
        end
    end
  end
end
