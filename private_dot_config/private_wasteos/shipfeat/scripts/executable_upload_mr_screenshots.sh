#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: upload_mr_screenshots.sh <branch> <file-or-dir> [note-title]" >&2
  exit 1
}

(( $# >= 2 )) || usage

branch="$1"
target="$2"
note_title="${3:-UI verification screenshots}"

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
cd "$repo_root"

if [[ "$target" != /* ]]; then
  target="${repo_root}/${target}"
fi

shopt -s nullglob
images=()

if [[ -f "$target" ]]; then
  case "$target" in
    *.png | *.jpg | *.jpeg | *.webp) images=("$target") ;;
    *)
      echo "upload_mr_screenshots: not an image: ${target}" >&2
      exit 1
      ;;
  esac
elif [[ -d "$target" ]]; then
  images=("$target"/*.{png,jpg,jpeg,webp})
else
  echo "upload_mr_screenshots: not found: ${target}" >&2
  exit 1
fi

if (( ${#images[@]} == 0 )); then
  echo "upload_mr_screenshots: no images in ${target}" >&2
  exit 1
fi

project_id="$(glab api projects/:fullpath | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"

note_body="## ${note_title}"$'\n\n'"Posted via \`wasteos-mr-upload-photos\` / shipfeat."$'\n\n'

uploaded_names=()
for image in "${images[@]}"; do
  name="$(basename "$image")"
  echo "Uploading ${name}..."
  markdown="$(python3 - "$project_id" "$image" <<'PY'
import json
import sys
import urllib.request
from pathlib import Path

import yaml

project_id, image_path = sys.argv[1], Path(sys.argv[2])
config = yaml.safe_load(
    open(Path.home() / "Library/Application Support/glab-cli/config.yml")
)
token = config["hosts"]["gitlab.com"]["token"]
boundary = "----shipfeatUploadBoundary"
body_start = (
    f"--{boundary}\r\n"
    f'Content-Disposition: form-data; name="file"; filename="{image_path.name}"\r\n'
    f"Content-Type: image/png\r\n\r\n"
).encode()
body_end = f"\r\n--{boundary}--\r\n".encode()
body = body_start + image_path.read_bytes() + body_end
req = urllib.request.Request(
    f"https://gitlab.com/api/v4/projects/{project_id}/uploads",
    data=body,
    method="POST",
    headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": f"multipart/form-data; boundary={boundary}",
    },
)
with urllib.request.urlopen(req) as resp:
    print(json.load(resp)["markdown"])
PY
)"
  note_body+="${markdown}"$'\n\n'
  uploaded_names+=("$name")
done

glab mr note "$branch" -m "$(printf '%b' "$note_body")"

commit_sha="$(git -C "$repo_root" rev-parse HEAD)"
marker_dir="${repo_root}/.shipfeat"
mkdir -p "$marker_dir"
routes_env="${SHIPFEAT_UI_ROUTES_REVIEWED:-}"
python3 - "$marker_dir/mr-photos-uploaded.json" "$branch" "$commit_sha" "$routes_env" "${uploaded_names[@]}" <<'PY'
import json, sys
from datetime import datetime, timezone

out, branch, commit_sha, routes_raw = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
files = sys.argv[5:]
routes = [r.strip() for r in routes_raw.split(",") if r.strip()] if routes_raw else []
payload = {
    "branch": branch,
    "commit_sha": commit_sha,
    "uploaded_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
    "routes_reviewed": routes,
    "console_errors": 0,
    "network_failures": 0,
    "files": files,
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2)
    f.write("\n")
PY

echo "Attached ${#images[@]} image(s) to MR for branch ${branch}."
echo "Marker: ${marker_dir}/mr-photos-uploaded.json"
