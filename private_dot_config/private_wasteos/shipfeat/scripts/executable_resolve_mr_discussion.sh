#!/usr/bin/env bash
# Reply on a GitLab MR discussion and resolve it — only after branch is pushed.
set -euo pipefail

usage() {
  echo "Usage: resolve_mr_discussion.sh <mr_iid> <discussion_id> <reply-body-file>" >&2
  echo "  Or:  resolve_mr_discussion.sh <mr_iid> <discussion_id> -m \"message\"" >&2
  exit 1
}

(( $# >= 3 )) || usage

mr_iid="$1"
discussion_id="$2"
shift 2

if [[ "$1" == "-m" ]]; then
  [[ -n "${2:-}" ]] || usage
  body="$2"
else
  body_file="$1"
  [[ -f "$body_file" ]] || {
    echo "resolve_mr_discussion: missing ${body_file}" >&2
    exit 1
  }
  body="$(<"$body_file")"
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
"${script_dir}/require_branch_pushed.sh" || {
  echo "resolve_mr_discussion: blocked — push all commits before resolving" >&2
  exit 1
}

glab api "projects/:id/merge_requests/${mr_iid}/discussions/${discussion_id}/notes" \
  --method POST --raw-field "body=${body}"

glab api "projects/:id/merge_requests/${mr_iid}/discussions/${discussion_id}" \
  --method PUT --raw-field "resolved=true"

echo "resolve_mr_discussion: replied and resolved ${discussion_id}"
