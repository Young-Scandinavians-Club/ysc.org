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

  Wrapping those deploys in #1762 ran the query-console steps from the
  repo root so the retry script was found. flyctl --local-only then used
  the main app as the Docker context. v2.53.0 and v2.53.1 failed in
  **Deploy query console sandbox** with:

      Cannot compile dependency :blurhash because it isn't available,
      please ensure the dependency is at "vendor/blurhash"
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
  @query_console_dockerfile Path.expand(
                              "../../query_console/Dockerfile",
                              __DIR__
                            )
  @query_console_mix Path.expand("../../query_console/mix.exs", __DIR__)
  @app_mix Path.expand("../../mix.exs", __DIR__)

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

  test "query console --local-only deploys keep Docker context in query_console/" do
    prod = File.read!(@prod_workflow)

    # #1762 invoked flyctl from the repo root with -c query_console/fly.*.toml.
    # flyctl --local-only uses cwd as the build context, so COPY mix.exs was
    # the main app (path-dep vendor/blurhash). v2.53.0 run 41118049812 and
    # v2.53.1 run 41131633952 failed mix deps.compile four times.
    refute prod =~ "-c query_console/fly.sandbox.toml"
    refute prod =~ "-c query_console/fly.prod.toml"
    assert prod =~ "bash ../etc/scripts/flyctl_deploy_retry.sh"
    assert prod =~ "-c fly.sandbox.toml"
    assert prod =~ "-c fly.prod.toml"

    for name <- [
          "Deploy query console to Fly.io sandbox",
          "Deploy query console to Fly.io production"
        ] do
      body = query_console_deploy_step(prod, name)

      refute body =~ ~r/^\s+working-directory:\s*\./m,
             "#{name} must keep the job default cwd query_console/ so Docker context is the console app"

      assert body =~ "../etc/scripts/flyctl_deploy_retry.sh"
      assert body =~ "--local-only"
    end
  end

  test "query console image compiles query_console mix.exs, not the main app" do
    dockerfile = File.read!(@query_console_dockerfile)
    console_mix = File.read!(@query_console_mix)
    app_mix = File.read!(@app_mix)

    assert dockerfile =~ "COPY mix.exs mix.lock"
    assert dockerfile =~ "rel/query_console"
    assert console_mix =~ "app: :query_console"
    refute console_mix =~ "vendor/blurhash"
    assert app_mix =~ ~s(path: "vendor/blurhash")
  end

  test "retry script documents the v2.52.0 local-only push 502" do
    script = File.read!(@script)

    assert script =~ "FLYCTL_DEPLOY_ATTEMPTS"
    assert script =~ "--local-only"
    assert script =~ "502"
    assert script =~ "ysc-prod"
    assert script =~ "retrying in"
    assert script =~ "query_console"
    assert script =~ "vendor/blurhash"
  end

  test "flyctl_deploy_retry.sh --self-test" do
    {output, status} =
      System.cmd(@script, ["--self-test"], stderr_to_stdout: true)

    assert status == 0, output
    assert output =~ "self-test passed"
  end

  defp query_console_deploy_step(prod, name) do
    pattern =
      ~r/(?s)- name: #{Regex.escape(name)}\n(.*?)(?:\n      - name: |\n  [a-z_]+:)/

    case Regex.run(pattern, prod) do
      [_, body] ->
        body

      _ ->
        flunk("missing production workflow step #{name}")
    end
  end
end
