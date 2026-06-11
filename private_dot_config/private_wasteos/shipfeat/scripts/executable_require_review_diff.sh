#!/usr/bin/env bash
# Tier M/L: require review-findings-status.json with every finding dispositioned.
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
profile="${repo_root}/.shipfeat/feature-profile.json"
status_file="${repo_root}/.shipfeat/review-findings-status.json"
findings_md="${repo_root}/.shipfeat/review-findings.md"

[[ -f "$profile" ]] || exit 0

tier="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("tier","M"))' "$profile")"
if [[ "$tier" == "S" ]]; then
  exit 0
fi

[[ -f "$findings_md" ]] || {
  echo "require_review_diff: missing ${findings_md} — run shipfeat review-diff" >&2
  exit 1
}

[[ -f "$status_file" ]] || {
  echo "require_review_diff: missing ${status_file}" >&2
  exit 1
}

python3 - "$status_file" "$(git -C "$repo_root" rev-parse HEAD)" <<'PY'
import json, sys

path, head = sys.argv[1], sys.argv[2]
data = json.loads(open(path, encoding="utf-8").read())
if data.get("head_sha") and data["head_sha"] != head:
    print(
        f"require_review_diff: status is for {data['head_sha'][:8]}, HEAD is {head[:8]} — re-run review-diff",
        file=sys.stderr,
    )
    raise SystemExit(1)

findings = data.get("findings") or []
allowed = {
    "accepted_fixed",
    "accepted_not_fixed_with_reason",
    "rejected_with_reason",
    "needs_human",
}
if not findings:
    # Allow explicit clean review: one finding with id "none" and disposition accepted_fixed
    print(
        "require_review_diff: add findings to review-findings-status.json "
        '(use id "none", summary "Clean review", disposition "accepted_fixed" if no issues)',
        file=sys.stderr,
    )
    raise SystemExit(1)

for i, f in enumerate(findings, 1):
    d = f.get("disposition")
    if d not in allowed:
        print(f"require_review_diff: finding {i} missing valid disposition (got {d!r})", file=sys.stderr)
        raise SystemExit(1)
    if d in ("accepted_not_fixed_with_reason", "rejected_with_reason", "needs_human") and not (f.get("note") or "").strip():
        print(f"require_review_diff: finding {i} requires a note for disposition {d}", file=sys.stderr)
        raise SystemExit(1)

print("require_review_diff: ok")
PY
