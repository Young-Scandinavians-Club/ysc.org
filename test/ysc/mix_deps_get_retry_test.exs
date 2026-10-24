defmodule Ysc.MixDepsGetRetryTest do
  @moduledoc """
  Guards the production Docker `mix deps.get` retry after hex.pm 500s.

  v2.49.1 Deploy Production (run 40112796404 / job 120929589166) failed in
  `mix deps.get --only prod`:

      Failed to fetch record for passbook from registry
      Internal Server Error
      ** (Mix) Unknown package passbook in lockfile

  Two cooperating bugs:

  1. Cache-mounting `/root/.mix` hid the Hex archive from the previous
     layer. Mix then auto-installed latest Hex (2.6.0) because locked deps
     call `Mix.Hex.ensure_installed?(true)`.
  2. Hex.pm returned 500 for one locked package. Mix reports that as
     "Unknown package in lockfile", so a single `mix deps.get` cannot
     distinguish a missing package from a registry blip.

  Tests passed on the same commit. Sandbox built the same Dockerfile about
  eight minutes earlier.
  """
  use ExUnit.Case, async: true

  @dockerfile Path.expand("../../etc/docker/Dockerfile", __DIR__)
  @dockerignore Path.expand("../../.dockerignore", __DIR__)
  @retry_script Path.expand("../../etc/scripts/mix_deps_get_retry.sh", __DIR__)
  @ci_workflow Path.expand("../../.github/workflows/ci.yml", __DIR__)

  test "prod image retries mix deps.get and does not overlay pinned Hex" do
    dockerfile = File.read!(@dockerfile)

    refute dockerfile =~ "target=/root/.mix",
           "cache-mounting /root/.mix hides the Hex installed in the previous layer"

    assert dockerfile =~ "mix_deps_get_retry.sh"
    assert dockerfile =~ "bash etc/scripts/mix_deps_get_retry.sh --only prod"
    assert dockerfile =~ ~r/^    bash$/m
  end

  test "prod Docker context includes every etc/ path the Dockerfile copies" do
    # `.dockerignore` excludes `etc/` and re-includes only named scripts.
    # #1710 copied mix_deps_get_retry.sh without a matching exception, so
    # sandbox buildx failed with "/etc/scripts/mix_deps_get_retry.sh": not found
    # (run 40116980063 / job 120944907022).
    dockerignore = File.read!(@dockerignore)
    dockerfile = File.read!(@dockerfile)

    copied_etc_paths =
      dockerfile
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "COPY "))
      |> Enum.reject(&String.contains?(&1, "--from="))
      |> Enum.map(fn line ->
        line
        |> String.split()
        |> Enum.drop(1)
        |> Enum.find(&String.starts_with?(&1, "etc/"))
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    assert copied_etc_paths != [],
           "expected the Dockerfile to COPY files under etc/"

    for path <- copied_etc_paths do
      assert File.exists?(Path.expand("../../#{path}", __DIR__)),
             "Dockerfile COPY source #{path} does not exist"

      assert dockerignore =~ "!#{path}",
             ".dockerignore excludes etc/ but does not re-include #{path}"
    end
  end

  test "CI runs the retry script self-test" do
    ci = File.read!(@ci_workflow)
    assert ci =~ "mix_deps_get_retry.sh --self-test"
  end

  test "mix_deps_get_retry.sh --self-test" do
    {output, status} =
      System.cmd(@retry_script, ["--self-test"], stderr_to_stdout: true)

    assert status == 0, output
    assert output =~ "self-test passed"
  end
end
