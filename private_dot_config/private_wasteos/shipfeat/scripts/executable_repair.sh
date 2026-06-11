#!/usr/bin/env bash
# Recover shipfeat session, MR recording, hooks, and watcher for an existing worktree.
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
cd "$repo_root"
tooling="$(shipfeat_tooling_root)"
script_dir="$(cd "$(dirname "$0")" && pwd)"

branch="$(git symbolic-ref --quiet --short HEAD)" || {
  echo "repair: not on a branch" >&2
  exit 1
}

agent="${SHIPFEAT_AGENT:-agent}"
session="${repo_root}/.shipfeat/session.json"

if [[ ! -f "$session" ]]; then
  echo "repair: creating session.json..."
  "${script_dir}/init_session.sh" "$branch" "$agent" "$repo_root"
else
  echo "repair: session.json present"
fi

if glab mr view "$branch" >/dev/null 2>&1; then
  echo "repair: recording MR for ${branch}..."
  "${script_dir}/record_mr_open.sh"
else
  echo "repair: no open MR for ${branch} (skip record_mr_open)"
fi

if [[ -x "${script_dir}/install_cursor_hooks.sh" ]]; then
  "${script_dir}/install_cursor_hooks.sh"
fi

mkdir -p "${repo_root}/.shipfeat/screenshots"

if [[ ! -f "${repo_root}/.shipfeat/ui-review.md" ]] && [[ -f "${tooling}/templates/ui-review.md" ]]; then
  if [[ -f "${repo_root}/.shipfeat/feature-profile.json" ]]; then
    needs_ui="$(python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); print("frontend_ui" in (p.get("change_types") or []) or p.get("requires_playwright_review"))' "${repo_root}/.shipfeat/feature-profile.json")"
    if [[ "$needs_ui" == "True" ]]; then
      cp "${tooling}/templates/ui-review.md" "${repo_root}/.shipfeat/ui-review.md"
      echo "repair: seeded .shipfeat/ui-review.md"
    fi
  fi
fi

if [[ ! -f "${repo_root}/.shipfeat/feature-profile.json" ]]; then
  echo "repair: copy ${tooling}/templates/feature-profile.example.json → .shipfeat/feature-profile.json and edit"
fi

echo ""
echo "repair: run shipfeat status (or ${script_dir}/status.sh) next"
"${script_dir}/status.sh"
