defmodule Ysc.FlyVerifyAppAccessTest do
  @moduledoc """
  Guards retries around `fly apps list --json` after empty/non-JSON output.

  v2.51.0 Deploy Production (run 40961012848 / job 123754475932) failed in
  **Deploy query console sandbox (gate before prod)** at
  `bash etc/scripts/fly_verify_app_access.sh ysc-query-console-sandbox`:

      json.decoder.JSONDecodeError: Expecting value: line 1 column 1 (char 0)
      FLY_API_TOKEN is set; flyctl uses it instead of 'fly auth login'.

  Tests on the same commit passed (run 40961009139 / job 123756214522,
  13m47s). The sibling **Deploy app sandbox** gate used the same
  `FLY_API_TOKEN` and flyctl v0.5.1 and printed
  `OK: Fly credentials can access app 'ysc-sandbox'` eight seconds later.
  Fly's flyctl_releases API was 503ing while flyctl was installed.
  """
  use ExUnit.Case, async: true

  @script Path.expand("../../etc/scripts/fly_verify_app_access.sh", __DIR__)
  @ci_workflow Path.expand("../../.github/workflows/ci.yml", __DIR__)
  @prod_workflow Path.expand(
                   "../../.github/workflows/fly-deploy-prod.yml",
                   __DIR__
                 )
  @sandbox_workflow Path.expand(
                      "../../.github/workflows/fly-deploy.yml",
                      __DIR__
                    )

  test "CI and deploy workflows still call fly_verify_app_access.sh" do
    ci = File.read!(@ci_workflow)
    prod = File.read!(@prod_workflow)
    sandbox = File.read!(@sandbox_workflow)

    assert ci =~ "fly_verify_app_access.sh --self-test"

    assert prod =~
             "bash etc/scripts/fly_verify_app_access.sh ysc-query-console-sandbox"

    assert prod =~ "bash etc/scripts/fly_verify_app_access.sh ysc-sandbox"

    assert sandbox =~
             "bash etc/scripts/fly_verify_app_access.sh ysc-query-console-sandbox"

    assert sandbox =~ "bash etc/scripts/fly_verify_app_access.sh ysc-sandbox"
  end

  test "script retries empty JSON instead of discarding flyctl stderr" do
    script = File.read!(@script)

    refute script =~ ~r/apps list --json 2>\/dev\/null/,
           "discarding flyctl stderr hid the empty apps-list response"

    assert script =~ "FLY_VERIFY_ATTEMPTS"
    assert script =~ "returned empty output"
    assert script =~ "retrying in"
  end

  test "fly_verify_app_access.sh --self-test" do
    {output, status} =
      System.cmd(@script, ["--self-test"], stderr_to_stdout: true)

    assert status == 0, output
    assert output =~ "self-test passed"
  end
end
