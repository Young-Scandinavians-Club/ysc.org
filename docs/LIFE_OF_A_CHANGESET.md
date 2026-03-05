# Life of a Changeset

This document explains how to contribute to the YSC project in detail: from creating a branch to merging your changes into `main`.

---

## Overview

```
main (up to date)
    │
    ├── Create branch: YOUR_NAME/NAME_OF_YOUR_CHANGE
    │
    ├── Make changes, run preflight, push
    │
    ├── Open PR against main
    │
    ├── Automated checks pass → Request review
    │
    └── After approval → Merge to main
```

---

## 1. Create a branch with a good name

**Always branch from an up-to-date `main`.**

```bash
git checkout main
git pull origin main
git checkout -b YOUR_NAME/NAME_OF_YOUR_CHANGE
```

### Branch naming convention

Use the format: **`YOUR_NAME/NAME_OF_YOUR_CHANGE`**

- **YOUR_NAME**: Your first name, nickname, or GitHub username (lowercase, no spaces).
- **NAME_OF_YOUR_CHANGE**: Short, descriptive name for the work (lowercase, use hyphens for multiple words).

**Examples:**

- `johan/recon-report-imp` — Johan’s reconciliation report improvements
- `alice/fix-login-rate-limit` — Alice’s fix for login rate limiting
- `bob/feature-booking-reminders` — Bob’s booking reminder feature

Avoid generic names like `fix` or `updates`. The name should make it easy to see what the branch is about.

---

## 2. Make your changes

- Implement your feature or fix following the project’s coding style and [AGENTS.md](../AGENTS.md) (and [STYLE_GUIDE.md](../STYLE_GUIDE.md) if applicable).
- Add or update tests for new behaviour or bug fixes.
- **Before committing**, run preflight so CI will pass:

```bash
make preflight
```

This runs compile, format, lint, Credo, Sobelow, dependency audit, and the full test suite. Fix any failures before pushing.

---

## 3. Push and open a Pull Request

Push your branch and open a PR **against `main`** (base branch = `main`).

```bash
git add -A
git commit -m "Short, clear commit message"
git push origin YOUR_NAME/NAME_OF_YOUR_CHANGE
```

Then in GitHub:

1. Open the repo and use “Compare & pull request” for your branch, or go to **Pull requests → New pull request**.
2. Set **base** to **`main`** and **compare** to your branch.
3. Fill in the PR description: what changed and why.
4. If you have a ticket from Linear (webtech team), reference it in the description.

---

## 4. Wait for automated checks to pass

CI (e.g. GitHub Actions) will run the same checks as `make preflight`.  

- If something fails, fix it on your branch and push again. Re-run `make preflight` locally before pushing.
- Do **not** ask for review until the automated checks are green.

---

## 5. Request review

Once all automated checks pass:

- Request review from the appropriate team members (e.g. web tech group).
- Address review comments by pushing new commits to the same branch. The PR will update automatically.

---

## 6. Merge the PR to main

After approval:

- Merge the PR into `main` (squash or merge commit per team preference).
- Delete the branch in GitHub if prompted or if that’s your workflow.
- Your changes are now on `main`.

---

## Quick reference

| Step | Action |
|------|--------|
| 1 | `git checkout main && git pull` then `git checkout -b YOUR_NAME/NAME_OF_YOUR_CHANGE` |
| 2 | Implement changes, add tests, run `make preflight` |
| 3 | Commit, push, open PR with base = `main` |
| 4 | Wait for CI to pass; fix and push if needed |
| 5 | Request review once checks are green |
| 6 | After approval, merge PR to `main` |

For day-to-day commands and workflows, see [QUICKREF.md](../QUICKREF.md). For full setup and contributing context, see the [Contributing section in README](../README.md#contributing).
