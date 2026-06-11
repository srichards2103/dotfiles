#!/usr/bin/env bash
# Poll GitLab MR notes; enqueue, reconcile, build prompt, dispatch.
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
cd "$repo_root"

session="${repo_root}/.shipfeat/session.json"
state="${repo_root}/.shipfeat/mr-watch-state.json"
stop_file="${repo_root}/.shipfeat/stop-mr-watch"
log="${repo_root}/.shipfeat/mr-watch.log"

if [[ ! -f "$session" ]]; then
  echo "watch_mr_comments: waiting for ${session}..." >&2
  while [[ ! -f "$session" ]]; do
    sleep 5
  done
fi

poll_sec="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("poll_interval_sec", 45))' "$session")"
branch="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["branch"])' "$session")"

echo "shipfeat MR watch: branch=${branch} poll=${poll_sec}s (Ctrl+C or touch .shipfeat/stop-mr-watch)" | tee -a "$log"

script_dir="$(cd "$(dirname "$0")" && pwd)"

while true; do
  if [[ -f "$stop_file" ]]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) stop file present — exiting" | tee -a "$log"
    exit 0
  fi

  if [[ ! -f "$session" ]]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) session.json removed — exiting" | tee -a "$log"
    exit 0
  fi

  mr_iid="$(python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get("mr_iid"); print(v if v else "")' "$session")"

  if [[ -z "$mr_iid" ]]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) waiting for MR (run open_mr / Phase 5)..." >>"$log"
    sleep "$poll_sec"
    continue
  fi

  mr_state="$(glab api "projects/:id/merge_requests/${mr_iid}" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("state",""))' 2>/dev/null || echo "")"
  if [[ "$mr_state" == "merged" || "$mr_state" == "closed" ]]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) MR ${mr_state} — watcher stopping" | tee -a "$log"
    exit 0
  fi

  "${script_dir}/reconcile_mr_discussions.sh" 2>>"$log" || true

  new_json="$("${script_dir}/fetch_new_mr_notes.py" "$mr_iid" "$state" "$session")"
  count="$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1])))' "$new_json")"

  if (( count > 0 )); then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) ${count} new MR note(s)" | tee -a "$log"
    tmp="${repo_root}/.shipfeat/.mr-notes-batch.json"
    printf '%s' "$new_json" >"$tmp"
    "${script_dir}/enqueue_mr_notes.sh" "$tmp"
  fi

  if "${script_dir}/build_mr_comment_prompt.sh" >>"$log" 2>&1; then
    "${script_dir}/dispatch_mr_comment.sh"
  fi

  sleep "$poll_sec"
done
