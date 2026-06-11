#!/usr/bin/env bash
# Fail if GitLab MR has unresolved discussions (unless human-blocked list).
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
cd "$repo_root"

session="${repo_root}/.shipfeat/session.json"
[[ -f "$session" ]] || {
  echo "require_no_unresolved_discussions: no session.json" >&2
  exit 1
}

mr_iid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["mr_iid"])' "$session")"
[[ -n "$mr_iid" && "$mr_iid" != "None" ]] || {
  echo "require_no_unresolved_discussions: mr_iid not set" >&2
  exit 1
}

blocked_file="${repo_root}/.shipfeat/human-blocked-discussions.json"
discussions_json="$(glab api "projects/:id/merge_requests/${mr_iid}/discussions" 2>/dev/null)" || {
  echo "require_no_unresolved_discussions: could not fetch discussions" >&2
  exit 1
}

python3 - "$discussions_json" "$blocked_file" <<'PY'
import json, sys
from pathlib import Path

discussions = json.loads(sys.argv[1])
blocked_path = Path(sys.argv[2])
blocked_ids = set()
if blocked_path.is_file():
    data = json.loads(blocked_path.read_text(encoding="utf-8"))
    if isinstance(data, list):
        blocked_ids = {str(x) for x in data}
    elif isinstance(data, dict):
        blocked_ids = {str(x) for x in data.get("discussion_ids", [])}

unresolved = []
for d in discussions:
    did = d.get("id")
    if str(did) in blocked_ids:
        continue
    notes = d.get("notes") or []
    if not notes:
        continue
    # GitLab: individual_note threads or resolvable discussions
    resolvable = d.get("individual_note") is False or any(
        n.get("resolvable") for n in notes
    )
    if not resolvable:
        continue
    if not d.get("resolved", False):
        first = notes[0]
        unresolved.append((did, first.get("author", {}).get("username"), first.get("body", "")[:80]))

if unresolved:
    print("require_no_unresolved_discussions: unresolved threads:", file=sys.stderr)
    for did, author, preview in unresolved:
        print(f"  discussion {did} @{author}: {preview!r}...", file=sys.stderr)
    print("Reply, resolve via resolve_mr_discussion.sh, or add id to .shipfeat/human-blocked-discussions.json", file=sys.stderr)
    raise SystemExit(1)

print("require_no_unresolved_discussions: ok (no unresolved discussions)")
PY
