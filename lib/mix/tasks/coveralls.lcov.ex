defmodule Mix.Tasks.Coveralls.Lcov do
  @moduledoc false
  use Mix.Task

  @shortdoc "Output the test coverage as an Lcov file"
  @preferred_cli_env :test

  @impl Mix.Task
  def run(args) do
    Ysc.Coveralls.compile_beams!(Mix.Project.compile_path())
    Mix.Tasks.Coveralls.do_run(args, type: "lcov")
  end
end
