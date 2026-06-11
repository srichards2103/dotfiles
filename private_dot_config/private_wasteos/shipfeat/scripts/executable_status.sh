#!/usr/bin/env bash
# Human-readable shipfeat state for the current feature worktree.
set -euo pipefail

# shellcheck source=_worktree_root.sh
# shellcheck source=_shipfeat_lib.sh
source "$(dirname "$0")/_worktree_root.sh"
source "$(dirname "$0")/_shipfeat_lib.sh"

repo_root="$(shipfeat_worktree_root)"
cd "$repo_root"

branch="$(git branch --show-current 2>/dev/null || echo '(detached)')"
echo "Branch: ${branch}"
echo "Worktree: ${repo_root}"

profile="${repo_root}/.shipfeat/feature-profile.json"
if [[ -f "$profile" ]]; then
  python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); print("Feature profile:", "tier="+p.get("tier","?"), "types="+",".join(p.get("change_types") or []))' "$profile"
else
  echo "Feature profile: missing (create .shipfeat/feature-profile.json)"
fi

session="${repo_root}/.shipfeat/session.json"
if [[ -f "$session" ]]; then
  python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print("Session:", "present", "mr_iid="+str(s.get("mr_iid")), "mr_url="+str(s.get("mr_url") or "—"))' "$session"
else
  echo "Session: missing (run: shipfeat repair)"
fi

if glab mr view "$branch" >/dev/null 2>&1; then
  glab mr view "$branch" 2>/dev/null | head -5 || true
else
  echo "MR (glab): none for branch"
fi

stop_file="${repo_root}/.shipfeat/stop-mr-watch"
if [[ -f "$stop_file" ]]; then
  echo "Watcher: stopped (.shipfeat/stop-mr-watch)"
elif pgrep -f "watch_mr_comments.sh" >/dev/null 2>&1; then
  echo "Watcher: running (watch_mr_comments.sh)"
else
  echo "Watcher: not running"
fi

watch_state="${repo_root}/.shipfeat/mr-watch-state.json"
if [[ -f "$watch_state" ]]; then
  python3 -c 'import json,sys; w=json.load(open(sys.argv[1])); print("Last watcher note_id:", w.get("last_note_id", "—"))' "$watch_state" 2>/dev/null || true
fi
if [[ -f "${repo_root}/.shipfeat/mr-watch.log" ]]; then
  echo "Last watcher log: $(tail -1 "${repo_root}/.shipfeat/mr-watch.log" 2>/dev/null || echo '—')"
fi

if [[ -f "${repo_root}/.shipfeat/pending-mr-comment-prompt.md" ]]; then
  echo "Pending MR comments: yes (prompt built)"
else
  echo "Pending MR comments: no"
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
if [[ -x "${script_dir}/mr_comment_ledger.py" ]]; then
  q="$(python3 "${script_dir}/mr_comment_ledger.py" queue-count "$repo_root" 2>/dev/null || echo 0)"
  echo "MR comment queue depth: ${q}"
fi
if [[ -f "${repo_root}/.shipfeat/mr-comment-ledger.md" ]]; then
  echo "MR ledger: .shipfeat/mr-comment-ledger.md"
fi
if [[ -f "${repo_root}/.shipfeat/commands.jsonl" ]]; then
  echo "Command log: $(wc -l < "${repo_root}/.shipfeat/commands.jsonl" | tr -d ' ') entries"
fi
if [[ -f "${repo_root}/.shipfeat/review-findings.md" ]]; then
  echo "Review diff: .shipfeat/review-findings.md"
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Working tree: dirty"
else
  echo "Working tree: clean"
fi

git fetch origin "$branch" 2>/dev/null || true
if git rev-parse --verify "origin/${branch}" >/dev/null 2>&1; then
  ahead="$(git rev-list --count "origin/${branch}..HEAD" 2>/dev/null || echo 0)"
  echo "Ahead of origin: ${ahead}"
else
  echo "Ahead of origin: (no upstream)"
fi

marker="${repo_root}/.shipfeat/mr-photos-uploaded.json"
if [[ -f "$marker" ]]; then
  python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); print("Screenshots uploaded:", "yes", "commit="+str(m.get("commit_sha","?")), "files="+str(len(m.get("files") or [])))' "$marker"
else
  echo "Screenshots uploaded: no"
fi

ui_review="${repo_root}/.shipfeat/ui-review.md"
[[ -f "$ui_review" ]] && echo "UI review file: present" || echo "UI review file: missing"

plan="${repo_root}/.shipfeat/plan.md"
if [[ -f "$plan" ]]; then
  open_tasks="$(grep -c '^\- \[ \]' "$plan" 2>/dev/null || echo 0)"
  echo "Plan open tasks: ${open_tasks}"
fi

blocked="${repo_root}/.shipfeat/human-blocked-discussions.json"
if [[ -f "$blocked" ]]; then
  echo "Human-blocked discussions: $(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$blocked" 2>/dev/null || echo '?')"
fi
