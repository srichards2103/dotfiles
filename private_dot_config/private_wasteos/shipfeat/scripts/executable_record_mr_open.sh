#!/usr/bin/env bash
# Update session.json after MR exists (call from open_mr.sh or Phase 5).
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
cd "$repo_root"

session="${repo_root}/.shipfeat/session.json"
[[ -f "$session" ]] || {
  echo "record_mr_open: no ${session} (run init_session first)" >&2
  exit 1
}

branch="$(git symbolic-ref --quiet --short HEAD)"
mr_json="$(glab api "projects/:id/merge_requests?source_branch=${branch}&state=opened" 2>/dev/null)" || true

if [[ -z "$mr_json" || "$mr_json" == "[]" ]]; then
  echo "record_mr_open: no open MR for ${branch}" >&2
  exit 1
fi

python3 - "$session" "$mr_json" <<'PY'
import json, sys

path, raw = sys.argv[1], sys.argv[2]
mrs = json.loads(raw)
mr = mrs[0]
with open(path, encoding="utf-8") as f:
    session = json.load(f)
session["mr_iid"] = mr["iid"]
session["mr_url"] = mr["web_url"]
session["mr_title"] = mr.get("title", "")
with open(path, "w", encoding="utf-8") as f:
    json.dump(session, f, indent=2)
    f.write("\n")
print(f"record_mr_open: iid={mr['iid']} url={mr['web_url']}")
PY

seed_script="$(dirname "$0")/seed_mr_watch_state.sh"
if [[ -x "$seed_script" ]]; then
  "$seed_script" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["mr_iid"])' "$session")"
fi
