#!/usr/bin/env bash
# Install shipfeat Cursor hooks + MR comment rule into the feature worktree (.cursor/ is gitignored).
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
cd "$repo_root"

shipfeat_home="$(cd "$(dirname "$0")/.." && pwd)"
hooks_src="${shipfeat_home}/hooks"
rules_src="${shipfeat_home}/templates"

mkdir -p "${repo_root}/.cursor/hooks" "${repo_root}/.cursor/rules"

# Copy real files (not symlinks) — Cursor loads project hooks from .cursor/hooks.json
cp "${hooks_src}/hooks.json" "${repo_root}/.cursor/hooks.json"
for script in shipfeat-mr-comment-stop.sh shipfeat-mr-comment-before-prompt.sh; do
  cp "${hooks_src}/${script}" "${repo_root}/.cursor/hooks/${script}"
  chmod +x "${repo_root}/.cursor/hooks/${script}"
done
cp "${rules_src}/shipfeat-mr-comments.mdc" "${repo_root}/.cursor/rules/shipfeat-mr-comments.mdc"

echo "cursor hooks: ${repo_root}/.cursor/hooks.json"
echo "cursor rule:  ${repo_root}/.cursor/rules/shipfeat-mr-comments.mdc"
