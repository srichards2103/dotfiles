#!/usr/bin/env bash
# Create docs/specs/<slug>/implementation-stages.md (+ goal-loop stub) for Tier L work.
set -euo pipefail

usage() {
  echo "Usage: scaffold_implementation_stages.sh <feature-slug> [feature-title]" >&2
  exit 1
}

(( $# >= 1 )) || usage
slug="$1"
title="${2:-${slug//-/ }}"

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
cd "$repo_root"
tooling="$(shipfeat_tooling_root)"
branch="$(git branch --show-current)"

spec_dir="${repo_root}/docs/specs/${slug}"
stages_file="${spec_dir}/implementation-stages.md"
goal_file="${spec_dir}/goal-loop-prompt.md"

mkdir -p "$spec_dir"

_subst() {
  local in_file=$1 out_file=$2
  sed \
    -e "s/{{FEATURE_SLUG}}/${slug}/g" \
    -e "s/{{FEATURE_TITLE}}/${title}/g" \
    -e "s/{{BRANCH}}/${branch}/g" \
    -e "s/{{STAGE_1_TITLE}}/Core backend/g" \
    -e "s/{{STAGE_2_TITLE}}/Frontend integration/g" \
    "$in_file" >"$out_file"
}

if [[ ! -f "$stages_file" ]]; then
  _subst "${tooling}/templates/implementation-stages.md" "$stages_file"
  echo "scaffold: wrote ${stages_file}"
else
  echo "scaffold: exists ${stages_file}"
fi

if [[ ! -f "$goal_file" ]]; then
  _subst "${tooling}/templates/goal-loop-prompt.stub.md" "$goal_file"
  echo "scaffold: wrote ${goal_file}"
else
  echo "scaffold: exists ${goal_file}"
fi

if [[ ! -f "${spec_dir}/design.md" ]]; then
  cat >"${spec_dir}/design.md" <<EOF
# ${title}

**Branch:** \`${branch}\`

## Summary

<!-- Authoritative design for Tier L work. -->

## Scope

## Out of scope

## Acceptance
EOF
  echo "scaffold: wrote ${spec_dir}/design.md (stub — fill in)"
fi
