#!/usr/bin/env bash
# Exit 0 only when the feature branch has no uncommitted work and is pushed to origin.
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
cd "$repo_root"

branch="$(git branch --show-current)"
[[ -n "$branch" ]] || {
  echo "require_branch_pushed: not on a branch" >&2
  exit 1
}

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "require_branch_pushed: uncommitted changes — commit and push before resolving MR threads or consuming the queue" >&2
  git status -sb >&2 || true
  exit 1
fi

git fetch origin "$branch" 2>/dev/null || true

upstream="origin/${branch}"
if git rev-parse --verify "$upstream" >/dev/null 2>&1; then
  ahead="$(git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)"
  if (( ahead > 0 )); then
    echo "require_branch_pushed: ${ahead} commit(s) on ${branch} not pushed to origin — push before resolving MR threads or consuming the queue" >&2
    git log --oneline "${upstream}..HEAD" >&2 || true
    exit 1
  fi
else
  echo "require_branch_pushed: no upstream origin/${branch} — push with: git push -u origin ${branch}" >&2
  exit 1
fi

echo "require_branch_pushed: ok (${branch} matches origin, working tree clean)"
