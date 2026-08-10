#!/usr/bin/env bash
# PR CI: detect email template changes, render HTML, screenshot, write PR comment markdown.
#
# Env (required in CI): BASE_SHA, HEAD_SHA
# For full run also: GITHUB_REPOSITORY, GITHUB_SHA
# Optional: GITHUB_OUTPUT, PR_NUMBER, COMMENT_DIR, PREVIEWS_DIR,
#           CAN_PUSH_PREVIEW_BRANCH, GITHUB_TOKEN, PLAYWRIGHT_NODE_PATH,
#           EMAIL_PREVIEWS_DETECT_ONLY=true
#
# Writes GITHUB_OUTPUT keys:
#   skip=true|false
#   render_all=true|false
#   templates=comma,separated,names   (when skip=false and render_all=false)
#   comment_path=...   — markdown for the sticky PR comment (full run only)
#   previews_dir=...   — directory containing HTML + PNG + manifest (full run only)

set -euo pipefail

: "${BASE_SHA:?BASE_SHA is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

write_output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s\n' "$1" >>"$GITHUB_OUTPUT"
  fi
}

# Shared layout / infrastructure — changes affect every email preview.
SHARED_PATHS=(
  "lib/ysc_web/emails/base_layout.ex"
  "lib/ysc_web/emails/templates/base_layout.mjml.eex"
  "lib/ysc_web/emails/header.ex"
  "lib/ysc_web/emails/footer.ex"
  "lib/ysc_web/emails/notification_settings_footer.ex"
  "lib/ysc_web/emails/helpers.ex"
  "priv/dev/notification_preview_samples.exs"
)

changed_files="$(
  git diff --name-only "${BASE_SHA}" "${HEAD_SHA}" -- \
    'lib/ysc_web/emails/' \
    'priv/dev/notification_preview_samples.exs' \
    2>/dev/null | sort -u || true
)"

if [ -z "${changed_files}" ]; then
  write_output "skip=true"
  write_output "render_all=false"
  write_output "templates="
  write_output "comment_path="
  write_output "previews_dir="
  exit 0
fi

render_all=false
templates=()

while IFS= read -r file; do
  [ -z "$file" ] && continue

  for shared in "${SHARED_PATHS[@]}"; do
    if [ "$file" = "$shared" ]; then
      render_all=true
      break
    fi
  done

  case "$file" in
    lib/ysc_web/emails/templates/*.mjml.eex)
      base="$(basename "$file" .mjml.eex)"
      if [ "$base" != "base_layout" ]; then
        templates+=("$base")
      fi
      ;;
    lib/ysc_web/emails/*.ex)
      base="$(basename "$file" .ex)"
      case "$base" in
        notifier | helpers | base_layout | header | footer | notification_settings_footer) ;;
        *)
          templates+=("$base")
          ;;
      esac
      ;;
  esac
done <<<"$changed_files"

# Deduplicate template names
if [ "${#templates[@]}" -gt 0 ]; then
  mapfile -t templates < <(printf '%s\n' "${templates[@]}" | sort -u)
fi

if [ "$render_all" != true ] && [ "${#templates[@]}" -eq 0 ]; then
  # e.g. only notifier.ex mapping changes with no template body change
  write_output "skip=true"
  write_output "render_all=false"
  write_output "templates="
  write_output "comment_path="
  write_output "previews_dir="
  exit 0
fi

templates_csv=""
if [ "${#templates[@]}" -gt 0 ]; then
  templates_csv="$(
    IFS=,
    echo "${templates[*]}"
  )"
fi

write_output "skip=false"
write_output "render_all=${render_all}"
write_output "templates=${templates_csv}"

if [ "${EMAIL_PREVIEWS_DETECT_ONLY:-}" = "true" ]; then
  write_output "comment_path="
  write_output "previews_dir="
  exit 0
fi

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"

COMMENT_DIR="${COMMENT_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/ysc-email-previews.XXXXXX")}"
PREVIEWS_DIR="${PREVIEWS_DIR:-${COMMENT_DIR}/previews}"
mkdir -p "$COMMENT_DIR" "$PREVIEWS_DIR"

if [ "$render_all" = true ]; then
  echo "Shared email layout/samples changed — rendering all templates"
  mix ci.email_previews --output-dir "$PREVIEWS_DIR" --all
else
  echo "Rendering changed templates: ${templates[*]}"
  mix ci.email_previews --output-dir "$PREVIEWS_DIR" --templates "${templates_csv}"
fi

# Screenshot HTML → PNG (serve priv/static for localhost image URLs in HTML)
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
NODE_PATH="${PLAYWRIGHT_NODE_PATH:-${NODE_PATH:-}}" \
  YSC_REPO_ROOT="${YSC_REPO_ROOT:-$REPO_ROOT}" \
  STATIC_ROOT="${STATIC_ROOT:-${REPO_ROOT}/priv/static}" \
  node "${SCRIPT_DIR}/screenshot_email_previews.mjs" "$PREVIEWS_DIR"

# Publish images to a per-PR branch so the sticky comment can embed them.
# Same-repo PRs only (forks cannot push with GITHUB_TOKEN).
image_base=""
if [ -n "${PR_NUMBER:-}" ] && [ "${CAN_PUSH_PREVIEW_BRANCH:-}" = "true" ]; then
  branch="ci/email-preview/pr-${PR_NUMBER}"
  publish_dir="${COMMENT_DIR}/publish"
  mkdir -p "$publish_dir"
  cp "$PREVIEWS_DIR"/*.png "$publish_dir/" 2>/dev/null || true

  if compgen -G "${publish_dir}/*.png" >/dev/null; then
    (
      cd "$publish_dir"
      git init -q
      git checkout -q -b "$branch"
      git config user.name "github-actions[bot]"
      git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
      git add ./*.png
      git commit -q -m "Email previews for PR #${PR_NUMBER} @ ${GITHUB_SHA}"
      git remote add origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
      git push -q -f origin "HEAD:refs/heads/${branch}"
    )
    # github.com/.../raw/... works for private repos for authenticated viewers
    image_base="https://github.com/${GITHUB_REPOSITORY}/raw/${branch}"
  fi
fi

# Build sticky comment markdown
comment_path="${COMMENT_DIR}/comment.md"
{
  echo "<!-- ci-email-previews -->"
  echo "## Email template previews"
  echo
  echo "Screenshots of email templates changed in this PR (sample data from \`priv/dev/notification_preview_samples.exs\`)."
  echo
  echo "<sub>Commit \`${GITHUB_SHA:0:7}\` · updated automatically on each push</sub>"
  echo

  if [ ! -f "${PREVIEWS_DIR}/manifest.json" ]; then
    echo "_No previews were generated._"
  else
    shopt -s nullglob
    pngs=("$PREVIEWS_DIR"/*.png)
    shopt -u nullglob

    if [ "${#pngs[@]}" -eq 0 ]; then
      echo "_HTML rendered but no screenshots were produced._"
    else
      for png in "${pngs[@]}"; do
        name="$(basename "$png" .png)"
        echo "### \`${name}\`"
        echo
        if [ -n "$image_base" ]; then
          # Cache-bust so the sticky comment shows the new image after force-push
          echo "![${name}](${image_base}/${name}.png?raw=true&v=${GITHUB_SHA})"
        else
          echo "_Screenshot generated (see workflow artifacts) — image hosting skipped (fork PR or push disabled)._"
        fi
        echo
      done
    fi
  fi
} >"$comment_path"

write_output "comment_path=${comment_path}"
write_output "previews_dir=${PREVIEWS_DIR}"
