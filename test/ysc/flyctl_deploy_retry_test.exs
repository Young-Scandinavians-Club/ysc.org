defmodule Ysc.FlyctlDeployRetryTest do
  @moduledoc """
  Guards retries around `flyctl deploy --local-only` after Fly registry 502s.

  v2.52.0 Deploy Production (run 41090055389 / job 124185686654) failed in
  **Deploy app production** after a successful local Docker compile:

      Error: failed to fetch an image or build from source: error rendering
      push status stream: unknown: failed to copy: unexpected status from PUT
      request to https://registry.fly.io/v2/ysc-prod/blobs/uploads/...: 502
      Bad Gateway

  Tests and the sandbox gate on the same tag passed (run 41090051589).
  CI sandbox deploys already wrap `flyctl deploy --image` with
  `flyctl_deploy_retry.sh` (PR #1589). Production still called bare
  `flyctl deploy --dockerfile --local-only`, so a single registry 502
  failed the release after ~10 minutes of compile.
  """
  use ExUnit.Case, async: true

  @script Path.expand("../../etc/scripts/flyctl_deploy_retry.sh", __DIR__)
  @ci_workflow Path.expand("../../.github/workflows/ci.yml", __DIR__)
  @prod_workflow Path.expand(
                   "../../.github/workflows/fly-deploy-prod.yml",
                   __DIR__
                 )
  @sandbox_workflow Path.expand(
                      "../../.github/workflows/fly-deploy.yml",
                      __DIR__
                    )

  test "CI still runs the retry script self-test" do
    ci = File.read!(@ci_workflow)
    assert ci =~ "flyctl_deploy_retry.sh --self-test"
  end

  test "sandbox CI deploys still go through flyctl_deploy_retry.sh --image" do
    sandbox = File.read!(@sandbox_workflow)

    assert sandbox =~ "bash etc/scripts/flyctl_deploy_retry.sh"
    assert sandbox =~ "--image registry.fly.io/ysc-sandbox:"
    assert sandbox =~ "--image registry.fly.io/ysc-query-console-sandbox:"
  end

  test "production deploys retry flyctl instead of calling it once" do
    prod = File.read!(@prod_workflow)

    refute Regex.match?(~r/^\s+flyctl deploy\b/m, prod),
           "bare flyctl deploy has no registry 502 retry; wrap with flyctl_deploy_retry.sh"

    assert prod =~ "bash etc/scripts/flyctl_deploy_retry.sh"
    assert prod =~ "-a ysc-prod"
    assert prod =~ "-a ysc-sandbox"
    assert prod =~ "-a ysc-query-console"
    assert prod =~ "-a ysc-query-console-sandbox"
    assert prod =~ "--local-only"
    assert prod =~ "--dockerfile etc/docker/Dockerfile"
  end

  test "retry script documents the v2.52.0 local-only push 502" do
    script = File.read!(@script)

    assert script =~ "FLYCTL_DEPLOY_ATTEMPTS"
    assert script =~ "--local-only"
    assert script =~ "502"
    assert script =~ "ysc-prod"
    assert script =~ "retrying in"
  end

  test "flyctl_deploy_retry.sh --self-test" do
    {output, status} =
      System.cmd(@script, ["--self-test"], stderr_to_stdout: true)

    assert status == 0, output
    assert output =~ "self-test passed"
  end
end
