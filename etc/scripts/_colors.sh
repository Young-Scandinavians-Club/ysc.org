#!/usr/bin/env bash
# _colors.sh - Shared terminal color variables. Source this file; do not execute it.
# Guards against non-TTY environments (CI, piped output) where tput would fail or produce garbage.

if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
  BOLD=$(tput bold)
  RESET=$(tput sgr0)
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  TEAL=$(tput setaf 6)
else
  BOLD=""
  RESET=""
  RED=""
  GREEN=""
  YELLOW=""
  TEAL=""
fi

export BOLD RESET RED GREEN YELLOW TEAL
