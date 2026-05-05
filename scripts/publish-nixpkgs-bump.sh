#!/usr/bin/env bash
# publish-nixpkgs-bump.sh - open a nixpkgs PR bumping apfel-llm to the local .version.
#
# Designed to run as the final, NON-FATAL step of `make release`. Also safe
# to run standalone (e.g. for catch-up bumps) since it's idempotent at every
# layer: fork creation, branch existence, PR existence.
#
# Why local-only (no GitHub Actions): cross-org PR creation requires a classic
# PAT with public_repo scope; running locally we use the existing interactive
# `gh auth login` session and avoid storing any long-lived credential.
#
# Usage:
#   ./scripts/publish-nixpkgs-bump.sh                   # uses .version
#   ./scripts/publish-nixpkgs-bump.sh --version 1.3.3   # explicit
#   ./scripts/publish-nixpkgs-bump.sh --dry-run         # no fork/push/PR
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
NIXPKGS_DIR="${NIXPKGS_BUMP_DIR:-$HOME/dev/nixpkgs-bump}"
UPSTREAM="NixOS/nixpkgs"
FORK="Arthur-Ficial/nixpkgs"
PACKAGE_PATH="pkgs/by-name/ap/apfel-llm/package.nix"

version=""
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$version" ]]; then
  version=$(cat "$REPO_ROOT/.version")
fi

if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERR: invalid version '$version' (expected X.Y.Z)" >&2
  exit 1
fi

warn() { echo "WARN: $*" >&2; }
info() { echo "===> $*"; }

# --- Tool checks (non-fatal: warn and skip if missing) ---
need_skip=false
for tool in gh git nix-prefetch-url python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    warn "$tool not found - skipping nixpkgs bump"
    need_skip=true
  fi
done

if $need_skip; then
  warn "Run manually later with: $0 --version $version"
  exit 0
fi

# gh auth status exits non-zero if ANY configured account is broken (even with
# a valid active one). The reliable health check is `gh api user` against the
# active account.
if ! gh api user >/dev/null 2>&1; then
  warn "gh CLI not authenticated to an active account - skipping nixpkgs bump"
  warn "Run 'gh auth login' then retry: $0 --version $version"
  exit 0
fi

# --- Ensure fork exists ---
info "Ensuring fork $FORK exists..."
if ! gh repo view "$FORK" >/dev/null 2>&1; then
  if $dry_run; then
    info "[dry-run] would: gh repo fork $UPSTREAM --clone=false"
  else
    gh repo fork "$UPSTREAM" --clone=false --remote=false >/dev/null
    # GitHub fork creation is async; wait for it to be queryable.
    for i in $(seq 1 20); do
      if gh repo view "$FORK" >/dev/null 2>&1; then break; fi
      sleep 2
    done
    gh repo view "$FORK" >/dev/null 2>&1 || { warn "fork did not appear after 40s"; exit 0; }
  fi
fi

# --- Maintain local checkout ---
if [[ ! -d "$NIXPKGS_DIR/.git" ]]; then
  info "Cloning fork to $NIXPKGS_DIR (one-time, ~1 min)..."
  if $dry_run; then
    info "[dry-run] would: git clone --filter=blob:none $FORK $NIXPKGS_DIR"
  else
    mkdir -p "$(dirname "$NIXPKGS_DIR")"
    git clone --filter=blob:none "https://github.com/$FORK.git" "$NIXPKGS_DIR" --quiet
  fi
fi

if ! $dry_run; then
  cd "$NIXPKGS_DIR"

  # Configure remotes idempotently
  if ! git remote get-url upstream >/dev/null 2>&1; then
    git remote add upstream "https://github.com/$UPSTREAM.git"
  fi
  # Ensure 'origin' uses gh's auth so push works without a stored PAT
  origin_url=$(git remote get-url origin)
  if [[ "$origin_url" != *"x-access-token"* ]]; then
    token=$(gh auth token)
    git remote set-url origin "https://x-access-token:${token}@github.com/$FORK.git"
  fi

  git config user.name "Arthur Ficial"
  git config user.email "arti.ficial@fullstackoptimization.com"

  info "Syncing fork master with upstream..."
  git fetch upstream master --quiet
  git checkout master --quiet 2>/dev/null || git checkout -b master upstream/master --quiet
  git reset --hard upstream/master --quiet

  # Read old version BEFORE editing so the commit message is accurate
  old_version=$(grep -E '^\s*version = "' "$PACKAGE_PATH" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')

  if [[ "$old_version" == "$version" ]]; then
    info "nixpkgs already at $version - nothing to do"
    exit 0
  fi

  branch="apfel-llm-${version}"
  info "Creating branch $branch (old: $old_version, new: $version)..."
  git checkout -B "$branch" --quiet

  info "Running scripts/bump-nixpkgs.sh..."
  "$REPO_ROOT/scripts/bump-nixpkgs.sh" \
    --version "$version" \
    --file "$NIXPKGS_DIR/$PACKAGE_PATH"

  if git diff --quiet -- "$PACKAGE_PATH"; then
    info "package.nix unchanged after bump - skipping"
    exit 0
  fi

  commit_msg="apfel-llm: ${old_version} -> ${version}"
  git add "$PACKAGE_PATH"
  git commit -m "$commit_msg" --quiet
  info "Pushing $branch to fork..."
  git push origin "$branch" --force --quiet

  # --- Open or update PR ---
  pr_title="$commit_msg"
  pr_body="Bumps apfel-llm to ${version}.

Release: https://github.com/Arthur-Ficial/apfel/releases/tag/v${version}

This PR was opened automatically by \`scripts/publish-nixpkgs-bump.sh\` as a step of the apfel release flow. The package's \`passthru.updateScript\` (\`nix-update-script\`) would produce the same diff."

  existing_pr=$(gh pr list --repo "$UPSTREAM" --state open \
    --head "Arthur-Ficial:${branch}" --json url --jq '.[0].url' 2>/dev/null || true)

  if [[ -n "$existing_pr" && "$existing_pr" != "null" ]]; then
    info "PR already open: $existing_pr"
  else
    info "Opening PR on $UPSTREAM..."
    pr_url=$(gh pr create \
      --repo "$UPSTREAM" \
      --base master \
      --head "Arthur-Ficial:${branch}" \
      --title "$pr_title" \
      --body "$pr_body")
    info "PR opened: $pr_url"
  fi
else
  info "[dry-run] would: sync, branch, bump, commit, push, open PR for v$version"
fi

info "Done."
