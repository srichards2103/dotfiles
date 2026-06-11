#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

# shipfeat_tooling_root used after record_mr_open

repo_root="$(shipfeat_worktree_root)"
cd "$repo_root"

branch="$(git symbolic-ref --quiet --short HEAD)" || {
  echo "open_mr: not on a branch" >&2
  exit 1
}

target="${OPENMR_TARGET:-develop}"
title="${OPENMR_TITLE:-$branch}"

git push -u origin "$branch"

if glab mr view "$branch" >/dev/null 2>&1; then
  echo "MR already exists for ${branch}"
else
  glab mr create \
    --source-branch "$branch" \
    --target-branch "$target" \
    --title "$title" \
    --fill \
    --yes
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"

session="${repo_root}/.shipfeat/session.json"
if [[ ! -f "$session" ]]; then
  agent="${SHIPFEAT_AGENT:-agent}"
  echo "open_mr: initializing session.json (agent=${agent})..."
  "${script_dir}/init_session.sh" "$branch" "$agent" "$repo_root"
fi

"${script_dir}/record_mr_open.sh"
"${script_dir}/shipfeat_mr_status.sh" --require-ready

glab mr view "$branch" --web
