#!/usr/bin/env bash
# Lists shell scripts that are not excluded by any .gitignore file.
set -euo pipefail

git ls-files --cached --others --exclude-standard -- '*.sh'
