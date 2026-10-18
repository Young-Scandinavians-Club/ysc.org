#!/usr/bin/env bash
# Fail fast when a restored Mix build artifact is missing hidden compile
# manifests.
#
# actions/upload-artifact omits `.*` paths unless include-hidden-files is
# true, so `_build/**/.mix/compile.elixir*` is dropped. Downstream jobs then
# recompile every dep; vix re-downloads its precompiled NIF from GitHub and
# can time out (run 39092969147 / job 117573798503, 2026-10-18).
#
# Usage:
#   ./etc/scripts/ci/assert_mix_build_manifests.sh _build/dev
#   ./etc/scripts/ci/assert_mix_build_manifests.sh _build/test
#   ./etc/scripts/ci/assert_mix_build_manifests.sh --self-test
set -euo pipefail

usage() {
  echo "Usage: $0 _build/<env>" >&2
  echo "       $0 --self-test" >&2
}

assert_manifests() {
  local build_path="${1:-}"
  local missing=0
  local file

  if [ -z "${build_path}" ]; then
    echo "assert_mix_build_manifests.sh: build path is required" >&2
    usage
    return 1
  fi

  if [ ! -d "${build_path}" ]; then
    echo "assert_mix_build_manifests.sh: ${build_path} is not a directory" >&2
    return 1
  fi

  for file in \
    "${build_path}/lib/vix/.mix/compile.elixir" \
    "${build_path}/lib/vix/.mix/compile.elixir_scm"; do
    if [ ! -f "${file}" ]; then
      echo "assert_mix_build_manifests.sh: missing Mix manifest ${file}" >&2
      missing=1
    fi
  done

  if [ "${missing}" -ne 0 ]; then
    echo "assert_mix_build_manifests.sh: upload-artifact must set include-hidden-files: true so _build/**/.mix/ is restored" >&2
    return 1
  fi

  echo "assert_mix_build_manifests.sh: Mix manifests present under ${build_path}/lib/vix/.mix"
}

self_test() {
  local tmp out

  if out="$(assert_manifests 2>&1)"; then
    echo "assert_mix_build_manifests.sh: expected missing build path to fail" >&2
    return 1
  fi
  if [[ "${out}" != *"build path is required"* ]]; then
    echo "assert_mix_build_manifests.sh: unexpected missing-path error: ${out}" >&2
    return 1
  fi

  tmp="$(mktemp -d)"
  if out="$(assert_manifests "${tmp}/missing" 2>&1)"; then
    echo "assert_mix_build_manifests.sh: expected missing directory to fail" >&2
    rm -rf "${tmp}"
    return 1
  fi
  if [[ "${out}" != *"is not a directory"* ]]; then
    echo "assert_mix_build_manifests.sh: unexpected missing-dir error: ${out}" >&2
    rm -rf "${tmp}"
    return 1
  fi

  mkdir -p "${tmp}/_build/dev/lib/vix/.mix"
  if out="$(assert_manifests "${tmp}/_build/dev" 2>&1)"; then
    echo "assert_mix_build_manifests.sh: expected missing manifests to fail" >&2
    rm -rf "${tmp}"
    return 1
  fi
  if [[ "${out}" != *"missing Mix manifest"* ]]; then
    echo "assert_mix_build_manifests.sh: unexpected missing-manifest error: ${out}" >&2
    rm -rf "${tmp}"
    return 1
  fi

  : >"${tmp}/_build/dev/lib/vix/.mix/compile.elixir"
  : >"${tmp}/_build/dev/lib/vix/.mix/compile.elixir_scm"
  out="$(assert_manifests "${tmp}/_build/dev")"
  if [[ "${out}" != *"Mix manifests present"* ]]; then
    echo "assert_mix_build_manifests.sh: unexpected success output: ${out}" >&2
    rm -rf "${tmp}"
    return 1
  fi

  rm -rf "${tmp}"
  echo "assert_mix_build_manifests.sh: self-test passed"
}

case "${1:-}" in
  --self-test)
    self_test
    ;;
  -h | --help)
    usage
    ;;
  "")
    usage
    exit 1
    ;;
  *)
    assert_manifests "$1"
    ;;
esac
