#!/usr/bin/env bash
# Canonical completion gate — run before telling the user the feature is done.
set -euo pipefail

# shellcheck source=_worktree_root.sh
# shellcheck source=_shipfeat_lib.sh
source "$(dirname "$0")/_worktree_root.sh"
source "$(dirname "$0")/_shipfeat_lib.sh"

repo_root="$(shipfeat_worktree_root)"
cd "$repo_root"
script_dir="$(cd "$(dirname "$0")" && pwd)"

profile="${repo_root}/.shipfeat/feature-profile.json"
[[ -f "$profile" ]] || {
  echo "shipfeat done: missing ${profile}" >&2
  exit 1
}

plan="${repo_root}/.shipfeat/plan.md"
if [[ -f "$plan" ]]; then
  open="$(grep -c '^\- \[ \]' "$plan" 2>/dev/null || echo 0)"
  if (( open > 0 )); then
    echo "shipfeat done: ${open} open task(s) in .shipfeat/plan.md" >&2
    exit 1
  fi
fi

"${script_dir}/require_branch_pushed.sh"
"${script_dir}/shipfeat_mr_status.sh" --require-ready

if [[ -f "${repo_root}/.shipfeat/pending-mr-comment-prompt.md" ]] || \
   [[ -f "${repo_root}/.shipfeat/mr-comment-ready.json" ]] || \
   [[ -f "${repo_root}/.shipfeat/mr-comment-active-batch.json" ]]; then
  echo "shipfeat done: pending MR comment batch — handle and consume_mr_comment_prompt.sh" >&2
  exit 1
fi

queued="$(python3 "${script_dir}/mr_comment_ledger.py" queue-count "$repo_root" 2>/dev/null || echo 0)"
if (( queued > 0 )); then
  echo "shipfeat done: ${queued} MR comment(s) still in queue" >&2
  exit 1
fi

"${script_dir}/require_commands_logged.sh"

"${script_dir}/require_no_unresolved_discussions.sh"

needs_ui="$(python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); print("frontend_ui" in (p.get("change_types") or []) or p.get("requires_playwright_review"))' "$profile")"
needs_photos="$needs_ui"

if [[ "$needs_ui" == "True" ]]; then
  "${script_dir}/require_ui_review.sh"
fi

if [[ "$needs_photos" == "True" ]]; then
  "${script_dir}/require_mr_photos_uploaded.sh"
fi

tier="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("tier","M"))' "$profile")"
if [[ "$tier" == "L" ]]; then
  if ! find "${repo_root}/docs/specs" -name 'implementation-stages.md' 2>/dev/null | grep -q .; then
    echo "shipfeat done: Tier L requires docs/specs/<feature>/implementation-stages.md" >&2
    exit 1
  fi
fi

if [[ "$tier" == "M" || "$tier" == "L" ]]; then
  "${script_dir}/require_review_diff.sh"
fi

echo "shipfeat done: all gates passed"
echo "  branch: $(git branch --show-current)"
echo "  commit: $(git rev-parse --short HEAD)"
python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print("  MR:", s.get("mr_url"))' "${repo_root}/.shipfeat/session.json"
