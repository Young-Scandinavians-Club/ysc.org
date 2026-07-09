#!/bin/sh
# Install the Hex version used across CI, Docker builds, and local dev.
# Hex 2.5.1 is not on hex.pm yet; 2.5.1-dev adds ignore_advisories for mix hex.audit.
# Revisit by 2026-07-22 and switch to: HEX_SOURCE=hexpm ./etc/scripts/install_hex.sh
set -eu

HEX_SOURCE="${HEX_SOURCE:-github}"
HEX_GITHUB_REF="${HEX_GITHUB_REF:-594ac3d3c4ca727eac6087adc21145eef3435df1}"

case "$HEX_SOURCE" in
  github)
    mix archive.install github hexpm/hex ref "$HEX_GITHUB_REF" --force
    ;;
  hexpm)
    mix local.hex --force
    ;;
  *)
    echo "install_hex.sh: unknown HEX_SOURCE=$HEX_SOURCE (expected github or hexpm)" >&2
    exit 1
    ;;
esac
