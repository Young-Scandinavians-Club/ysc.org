#!/usr/bin/env bash
# release.sh - Create a new release: update version in mix.exs, create git tag, commit and push.
# Pushing the v* tag triggers GitHub Actions production deploy (.github/workflows/fly-deploy-prod.yml).
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MIX_EXS="$PROJECT_ROOT/mix.exs"

# shellcheck source=_colors.sh
. "$SCRIPT_DIR/_colors.sh"

usage() {
  echo "Usage: $0 [TAG]"
  echo ""
  echo "Creates a new release by:"
  echo "  1. Updating the version in mix.exs"
  echo "  2. Creating a git tag"
  echo "  3. Committing and pushing the change and tag to main"
  echo ""
  echo "After push, CI deploys ysc-prod from etc/fly/fly-prod.toml (tag must be v*)."
  echo ""
  echo "TAG: Version tag (e.g. v1.0.0 or 1.0.0). If not provided, will prompt."
  exit 1
}

# Get tag from argument or prompt
if [ -n "${1:-}" ]; then
  TAG="$1"
else
  echo "${BOLD}Create new release${RESET}"
  echo ""
  read -rp "Enter version tag (e.g. v1.0.0): " TAG
  if [ -z "$TAG" ]; then
    echo "${RED}Error: Tag cannot be empty${RESET}"
    exit 1
  fi
fi

# Normalize tag: ensure it has 'v' prefix for git
GIT_TAG="$TAG"
if [[ ! "$GIT_TAG" =~ ^v ]]; then
  GIT_TAG="v$TAG"
fi

# Version for mix.exs: strip leading 'v' (Elixir convention)
MIX_VERSION="${GIT_TAG#v}"

# Validate version format (semver: x.y.z)
if [[ ! "$MIX_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$ ]]; then
  echo "${RED}Error: Invalid version format. Use semver (e.g. 1.0.0 or v1.0.0)${RESET}"
  exit 1
fi

cd "$PROJECT_ROOT"

# Check for uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
  echo "${RED}Error: Working directory has uncommitted changes. Commit or stash them first.${RESET}"
  git status --short
  exit 1
fi

# Check we're on main
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
  echo "${RED}Error: Must be on main branch (current: $BRANCH)${RESET}"
  exit 1
fi

# Sync with remote before making any changes to avoid a push rejection mid-release
echo "${TEAL}Syncing with origin/main...${RESET}"
git pull --rebase origin main
echo "${GREEN}✓ Up to date with origin/main${RESET}"
echo ""

# Check tag doesn't already exist (re-check after pull in case remote has it)
if git rev-parse "$GIT_TAG" >/dev/null 2>&1; then
  echo "${RED}Error: Tag $GIT_TAG already exists${RESET}"
  exit 1
fi

echo "${BOLD}═══════════════════════════════════════════════════════════════════════════${RESET}"
echo "${BOLD}                           Creating release $GIT_TAG${RESET}"
echo "${BOLD}═══════════════════════════════════════════════════════════════════════════${RESET}"
echo ""

# Update version in mix.exs
echo "${TEAL}[1/4] Updating version in mix.exs to $MIX_VERSION...${RESET}"
if [[ "$(uname)" == "Darwin" ]]; then
  sed -i '' "s/version: \"[^\"]*\"/version: \"$MIX_VERSION\"/" "$MIX_EXS"
else
  sed -i "s/version: \"[^\"]*\"/version: \"$MIX_VERSION\"/" "$MIX_EXS"
fi
echo "${GREEN}✓ mix.exs updated${RESET}"
echo ""

# Commit the change
echo "${TEAL}[2/4] Committing version bump...${RESET}"
git add "$MIX_EXS"
git commit -m "Bump version to $MIX_VERSION"
echo "${GREEN}✓ Committed${RESET}"
echo ""

# Create tag
echo "${TEAL}[3/4] Creating git tag $GIT_TAG...${RESET}"
git tag "$GIT_TAG"
echo "${GREEN}✓ Tag created${RESET}"
echo ""

# Push commit and tag
echo "${TEAL}[4/4] Pushing to main...${RESET}"
git push origin main
git push origin "$GIT_TAG"
echo "${GREEN}✓ Pushed to origin${RESET}"
echo ""

echo "${BOLD}═══════════════════════════════════════════════════════════════════════════${RESET}"
echo "${GREEN}${BOLD}                      Release $GIT_TAG created successfully!${RESET}"
echo "${BOLD}═══════════════════════════════════════════════════════════════════════════${RESET}"
echo ""
echo "${TEAL}Next: watch the GitHub Actions workflow \"Deploy Production\" for this tag.${RESET}"
