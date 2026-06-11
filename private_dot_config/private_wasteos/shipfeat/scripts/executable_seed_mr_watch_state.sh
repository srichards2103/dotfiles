#!/usr/bin/env bash
# Set last_note_id to current max so only future MR comments trigger dispatch.
set -euo pipefail

if (( $# != 1 )); then
  echo "Usage: seed_mr_watch_state.sh <mr_iid>" >&2
  exit 1
fi

mr_iid="$1"

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
state="${repo_root}/.shipfeat/mr-watch-state.json"

notes_raw="$(glab api "projects/:id/merge_requests/${mr_iid}/notes?per_page=100&sort=asc&order_by=created_at")"

python3 - "$state" "$notes_raw" <<'PY'
import json, sys, os

state_path, raw = sys.argv[1], sys.argv[2]
notes = json.loads(raw)
max_id = max((int(n["id"]) for n in notes), default=0)
state = {}
if os.path.isfile(state_path):
    with open(state_path, encoding="utf-8") as f:
        state = json.load(f)
state["last_note_id"] = max_id
state["seeded"] = True
with open(state_path, "w", encoding="utf-8") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
print(f"seed_mr_watch_state: last_note_id={max_id}")
PY
