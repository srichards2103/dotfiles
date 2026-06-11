#!/usr/bin/env bash
# Second-pass review: diff vs develop → review-findings.md (+ optional codex).
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
cd "$repo_root"
tooling="$(shipfeat_tooling_root)"
script_dir="$(cd "$(dirname "$0")" && pwd)"

profile="${repo_root}/.shipfeat/feature-profile.json"
if [[ -f "$profile" ]]; then
  tier="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("tier","M"))' "$profile")"
  if [[ "$tier" == "S" ]]; then
    echo "review_diff: skipped for tier S"
    exit 0
  fi
fi

base_ref="${SHIPFEAT_REVIEW_BASE:-develop}"
git fetch origin "$base_ref" 2>/dev/null || true
merge_base="$(git merge-base "origin/${base_ref}" HEAD 2>/dev/null || git merge-base "$base_ref" HEAD)"
head_sha="$(git rev-parse HEAD)"

diff_file="${repo_root}/.shipfeat/review-diff.patch"
prompt_file="${repo_root}/.shipfeat/review-diff-prompt.md"
findings_file="${repo_root}/.shipfeat/review-findings.md"
status_file="${repo_root}/.shipfeat/review-findings-status.json"

mkdir -p "${repo_root}/.shipfeat"
git diff "${merge_base}..HEAD" >"$diff_file"

{
  cat "${tooling}/templates/review-diff-instructions.md"
  echo ""
  echo "---"
  echo ""
  echo "Branch: $(git branch --show-current)"
  echo "Base: ${base_ref} (${merge_base})"
  echo "HEAD: ${head_sha}"
  echo ""
  echo "## Diff stat"
  git diff --stat "${merge_base}..HEAD"
  echo ""
  echo "Full patch: .shipfeat/review-diff.patch"
} >"$prompt_file"

reviewer="${SHIPFEAT_REVIEW_AGENT:-}"
if [[ -z "$reviewer" ]]; then
  if command -v codex >/dev/null 2>&1; then
    reviewer=codex
  fi
fi

if [[ "$reviewer" == "codex" ]] && command -v codex >/dev/null 2>&1; then
  echo "review_diff: running codex reviewer..."
  codex "$(<"$prompt_file")" >"$findings_file" 2>/dev/null || {
    echo "review_diff: codex failed — complete review manually using ${prompt_file}" >&2
  }
else
  cat >"$findings_file" <<EOF
# Review findings

Run a second-pass reviewer using:

  ${prompt_file}

Then fill dispositions in:

  ${status_file}

EOF
  echo "review_diff: wrote ${prompt_file} — run reviewer manually (set SHIPFEAT_REVIEW_AGENT=codex to auto-run)"
fi

if [[ ! -f "$status_file" ]]; then
  python3 - "$status_file" "$base_ref" "$head_sha" <<'PY'
import json, sys
from datetime import datetime, timezone

out, base, head = sys.argv[1:4]
payload = {
    "reviewed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
    "base_ref": base,
    "head_sha": head,
    "findings": [],
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2)
    f.write("\n")
PY
  echo "review_diff: seeded ${status_file} (add findings + dispositions)"
fi

echo "review_diff: patch=${diff_file} findings=${findings_file}"
