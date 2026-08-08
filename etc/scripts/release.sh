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
  echo "  1. Reviewing commits and diffs since the previous release tag"
  echo "  2. Updating the version in mix.exs"
  echo "  3. Creating a git tag"
  echo "  4. Committing and pushing the change and tag to main"
  echo ""
  echo "After push, CI deploys ysc-prod from etc/fly/fly-prod.toml (tag must be v*)."
  echo ""
  echo "TAG: Version tag (e.g. v1.0.0 or 1.0.0). If not provided, prompts (default: minor bump from highest v* tag)."
  exit 1
}

# Print commits and diffs that will ship in this release (previous v* tag..HEAD), then confirm.
review_release_diff() {
  local prev_tag="$1"
  local range
  local commit_count
  local show_diff
  local confirm

  echo "${BOLD}═══════════════════════════════════════════════════════════════════════════${RESET}"
  echo "${BOLD}                     Review changes for $GIT_TAG${RESET}"
  echo "${BOLD}═══════════════════════════════════════════════════════════════════════════${RESET}"
  echo ""

  if [ -z "$prev_tag" ]; then
    echo "${YELLOW}No previous v* tag — cannot bound a release range. Skipping diff review.${RESET}"
    echo ""
    read -rp "Proceed with release ${GIT_TAG}? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "${YELLOW}Aborted. No changes made.${RESET}"
      exit 0
    fi
    echo ""
    return 0
  fi

  range="${prev_tag}..HEAD"
  commit_count="$(git rev-list --count "$range")"
  echo "${TEAL}Range: ${BOLD}${range}${RESET} ${TEAL}(plus the version bump commit)${RESET}"
  echo ""

  if [ "$commit_count" -eq 0 ]; then
    echo "${YELLOW}No commits since ${prev_tag}. This release would only contain the version bump.${RESET}"
    echo ""
  else
    echo "${TEAL}Commits (${commit_count}):${RESET}"
    git log --oneline --no-decorate "$range"
    echo ""

    echo "${TEAL}Diffstat:${RESET}"
    git diff --stat "$range"
    echo ""

    read -rp "Show full diff? [y/N] " show_diff
    if [[ "$show_diff" =~ ^[Yy]$ ]]; then
      echo ""
      git --no-pager diff "$range"
      echo ""
    fi
  fi

  read -rp "Proceed with release ${GIT_TAG}? [y/N] " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "${YELLOW}Aborted. No changes made.${RESET}"
    exit 0
  fi
  echo ""
}

# Highest existing v* tag by semver (e.g. v1.12.0 over v1.11.9). Empty if none.
highest_version_tag() {
  git -C "$PROJECT_ROOT" tag -l 'v*' 2>/dev/null | LC_ALL=C sort -V | tail -n 1
}

# Next minor from semver core x.y.z in a tag (e.g. v1.2.3 -> 1.3.0). No prior tag or unparseable -> 0.1.0
suggest_next_minor() {
  local tag="${1:-}"
  local base="${tag#v}"
  if [[ "$base" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
    local major="${BASH_REMATCH[1]}"
    local minor="${BASH_REMATCH[2]}"
    echo "${major}.$((minor + 1)).0"
  else
    echo "0.1.0"
  fi
}

# True when $1 is strictly greater than $2 (semver; uses sort -V).
semver_gt() {
  local a="$1"
  local b="$2"
  [ "$a" != "$b" ] && [ "$(printf '%s\n' "$a" "$b" | LC_ALL=C sort -Vr | head -n 1)" = "$a" ]
}

validate_version_format() {
  local version="$1"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$ ]]; then
    echo "${RED}Error: Invalid version format. Use semver (e.g. 1.0.0 or v1.0.0)${RESET}"
    exit 1
  fi
}

normalize_tag_inputs() {
  local tag="$1"
  GIT_TAG="$tag"
  if [[ ! "$GIT_TAG" =~ ^v ]]; then
    GIT_TAG="v$tag"
  fi
  MIX_VERSION="${GIT_TAG#v}"
}

TAG="${1:-}"

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

# Sync with remote before prompting or validating so tags/versions match origin
echo "${TEAL}Syncing with origin/main...${RESET}"
git pull --rebase origin main
git fetch -q --tags origin 2>/dev/null || true
echo "${GREEN}✓ Up to date with origin/main${RESET}"
echo ""

HIGHEST_TAG="$(highest_version_tag)"

# Get tag from argument or prompt (after sync so defaults and checks use remote tags)
if [ -n "$TAG" ]; then
  normalize_tag_inputs "$TAG"
  validate_version_format "$MIX_VERSION"
else
  echo "${BOLD}Create new release${RESET}"
  echo ""
  if [ -n "$HIGHEST_TAG" ]; then
    echo "${TEAL}Highest release tag (semver): ${BOLD}${HIGHEST_TAG}${RESET}"
  else
    echo "${TEAL}Highest release tag (semver): ${BOLD}(none yet)${RESET}"
  fi
  DEFAULT_MIX="$(suggest_next_minor "$HIGHEST_TAG")"
  DEFAULT_GIT_TAG="v${DEFAULT_MIX}"
  echo ""
  echo "${TEAL}Default is a minor bump: ${BOLD}${DEFAULT_GIT_TAG}${RESET} — press ${BOLD}Enter${RESET} to use it, or type another version (e.g. v1.0.0 or 1.0.0)."
  read -rp "Version tag: " TAG
  if [ -z "$TAG" ]; then
    TAG="$DEFAULT_GIT_TAG"
  fi
  normalize_tag_inputs "$TAG"
  validate_version_format "$MIX_VERSION"
fi

# Re-check highest tag after any concurrent tag fetches during prompt
HIGHEST_TAG="$(highest_version_tag)"

# Check tag doesn't already exist
if git rev-parse "$GIT_TAG" >/dev/null 2>&1; then
  echo "${RED}Error: Tag $GIT_TAG already exists${RESET}"
  exit 1
fi

# New release must be strictly greater than the highest existing v* tag
if [ -n "$HIGHEST_TAG" ]; then
  HIGHEST_VERSION="${HIGHEST_TAG#v}"
  if ! semver_gt "$MIX_VERSION" "$HIGHEST_VERSION"; then
    echo "${RED}Error: Version $MIX_VERSION must be greater than latest release $HIGHEST_TAG${RESET}"
    exit 1
  fi
fi

review_release_diff "$HIGHEST_TAG"

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
