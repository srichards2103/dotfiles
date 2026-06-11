#!/usr/bin/env bash
# Exit 0 only if MR photos were uploaded for this worktree (shipfeat gate).
set -euo pipefail

# shellcheck source=_worktree_root.sh
# shellcheck source=_shipfeat_lib.sh
source "$(dirname "$0")/_worktree_root.sh"
source "$(dirname "$0")/_shipfeat_lib.sh"

repo_root="$(shipfeat_worktree_root)"
marker="${repo_root}/.shipfeat/mr-photos-uploaded.json"

if [[ ! -f "$marker" ]]; then
  echo "require_mr_photos_uploaded: missing ${marker}" >&2
  echo "Run: SHIPFEAT_HOME=\${SHIPFEAT_HOME:-\$HOME/.config/wasteos/shipfeat} \\"
  echo "  \"\${SHIPFEAT_HOME}/scripts/upload_mr_screenshots.sh\" \"\$(git branch --show-current)\" .shipfeat/screenshots" >&2
  exit 1
fi

branch="$(git -C "$repo_root" branch --show-current)"
python3 - "$marker" "$branch" "$repo_root" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

marker_path, branch, repo = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
m = json.loads(marker_path.read_text(encoding="utf-8"))

if m.get("branch") != branch:
    raise SystemExit(
        f"require_mr_photos_uploaded: marker is for branch {m.get('branch')}, current is {branch}"
    )

head = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
marker_sha = m.get("commit_sha")
if marker_sha and marker_sha != head:
    diff = subprocess.run(
        ["git", "-C", str(repo), "diff", "--name-only", f"{marker_sha}..HEAD", "--", "frontend/"],
        capture_output=True,
        text=True,
        check=False,
    )
    if diff.stdout.strip():
        raise SystemExit(
            "require_mr_photos_uploaded: frontend changed since screenshot upload "
            f"(marker {marker_sha[:8]} vs HEAD {head[:8]}) — re-run Playwright and upload_mr_screenshots.sh"
        )

files = m.get("files") or []
print(f"OK: MR photos uploaded for {branch} ({len(files)} file(s), commit={marker_sha or 'unknown'})")
PY
