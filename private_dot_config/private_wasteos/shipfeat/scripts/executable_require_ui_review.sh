#!/usr/bin/env bash
# Require .shipfeat/ui-review.md with checklist items ticked for frontend work.
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
ui_review="${repo_root}/.shipfeat/ui-review.md"
template="$(shipfeat_tooling_root)/templates/ui-review.md"

if [[ ! -f "$ui_review" ]]; then
  echo "require_ui_review: missing ${ui_review}" >&2
  echo "Copy template: cp ${template} ${ui_review}" >&2
  exit 1
fi

open="$(grep -c '^\- \[ \]' "$ui_review" 2>/dev/null || echo 0)"
if (( open > 0 )); then
  echo "require_ui_review: ${open} unchecked item(s) in Playwright walkthrough — complete ui-review.md" >&2
  exit 1
fi

if ! grep -q 'Screenshots uploaded' "$ui_review"; then
  echo "require_ui_review: missing Screenshots uploaded section" >&2
  exit 1
fi

echo "require_ui_review: ok"
