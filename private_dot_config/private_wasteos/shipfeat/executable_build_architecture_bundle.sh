#!/usr/bin/env bash
set -euo pipefail

BUNDLE="${1:-$HOME/.config/wasteos/shipfeat/SHIPFEAT_ARCHITECTURE_REVIEW_BUNDLE.txt}"
SHIPFEAT="$HOME/.config/wasteos/shipfeat"
SKILLS="$HOME/.config/wasteos/skills"
PL="${PL_WORKTREE:-$HOME/code/wasteos-feature-price-list-refactor}/docs/specs/price-list-refactor"

append_file() {
  local label="$1"
  local path="$2"
  {
    printf '\n################################################################################\n'
    printf '# FILE: %s\n' "$label"
    printf '# PATH: %s\n' "$path"
    printf '################################################################################\n\n'
    if [[ -f "$path" ]]; then
      /bin/cat "$path"
    else
      printf '[MISSING: %s]\n' "$path"
    fi
  } >>"$BUNDLE"
}

: >"$BUNDLE"

/bin/cat >>"$BUNDLE" <<'HEADER'
================================================================================
WASTEOS SHIPFEAT — COMPLETE ARCHITECTURE REVIEW BUNDLE (for ChatGPT / external review)
================================================================================
Generated: 2026-06-04
Purpose: Full source dump of shipfeat install + price-list steering reference + analysis.

HOW TO USE
----------
Review the complete tooling below. Part 1 is narrative/analysis; Parts 2+ are FULL
SOURCE FILES (scripts, zsh launcher, skills, hooks, templates).

Deliver:
  1. Unified Shipfeat v2 design (price-list steering + shipfeat automation)
  2. Gaps and failure modes in current shipfeat
  3. Prioritized improvements to scripts/workflow
  4. Answers to Part 1 questions

================================================================================
PART 1 — ANALYSIS (price-list pattern vs shipfeat)
================================================================================

PRICE-LIST SUCCESS PATTERN (docs/specs/price-list-refactor/)
- design.md — authoritative spec
- implementation-stages.md — durable ledger (checkboxes + commit SHAs)
- goal-loop-prompt.md — pasteable agent loop
- price_list_baseline.json — measurable terminal parity gate
- docs/steering/code-review-standard.md — quality gate (same as ~/.config/wasteos/)

Why it worked: durable state, one stage at a time, per-stage self-review, terminal
multi-reviewer gate, no scope invention.

SHIPFEAT TODAY (~/.config/wasteos/shipfeat/)
- Phases: scope → implement → drst → pytest → open MR → MR watcher → screenshots
- Ephemeral .shipfeat/plan.md vs committed implementation-stages.md
- MR loop: session.json + watch_mr_comments.sh + Cursor hooks + glab scripts

PROPOSED SHIPFEAT V2 (summary)
- Tier S/M/L features
- Tier L uses goal-loop + implementation-stages like price-list
- Terminal gate scaled by tier
- Always inject docs/steering in prompt.md
- Harden: open_mr requires session; setup-mr-loop for Cursor-only starts

OPEN QUESTIONS FOR REVIEWER
1. Commit implementation-stages.md on branch or gitignore?
2. Three tiers vs always split large work into multiple MRs?
3. Minimal terminal gate for small features?
4. Generalize baseline/parity beyond price-list?
5. code-review-standard in repo vs ~/.config only?
6. Auto Codex review in shipfeat?
7. Poll vs webhook for MR comments?
8. Script improvements (open_mr fallback init_session, etc.)?

INSTALL LAYOUT
  ~/.config/wasteos/shipfeat.zsh          — zsh entry + tmux launcher
  ~/.config/wasteos/shipfeat/             — SKILL.md, scripts/, hooks/, templates/
  ~/.config/wasteos/skills/               — wasteos-mr-comment-watch, wasteos-mr-upload-photos
  ~/.config/wasteos/shipfeat.env          — SHIPFEAT_APP_EMAIL, PASSWORD, HOST
  ~/.config/wasteos/code-review-standard.md

WORKTREE ARTIFACTS (.shipfeat/ gitignored)
  prompt.md, plan.md, summary.md, session.json
  pending-mr-comment-prompt.md, mr-comment-ready.json, mr-watch-state.json
  screenshots/, mr-photos-uploaded.json, mr-watch.log, stop-mr-watch

SCRIPT INDEX (full source in Part 4)
  _worktree_root.sh          — resolve worktree vs tooling paths
  init_session.sh            — session.json for MR watcher
  record_mr_open.sh          — set mr_iid after MR exists
  open_mr.sh                 — push + glab mr create
  seed_mr_watch_state.sh     — ignore existing MR notes
  watch_mr_comments.sh       — poll GitLab ~45s
  fetch_new_mr_notes.py      — filter new human notes
  dispatch_mr_comment.sh     — queue for Cursor/tmux agent
  require_branch_pushed.sh   — gate before resolve/consume
  resolve_mr_discussion.sh   — reply + resolve thread
  consume_mr_comment_prompt.sh — clear queue after push
  upload_mr_screenshots.sh  — GitLab upload API + mr note
  require_mr_photos_uploaded.sh — Phase 6 gate
  playwright_shipfeat_init.sh — 1920x1080 browser
  app_url.sh                 — nginx URL from .worktree.env
  wait_for_backend_ready.sh  — /api/common/readyz/
  run-agent.sh               — codex|claude|agent launcher
  install_cursor_hooks.sh  — copy hooks into worktree .cursor/
  trust_worktree.sh          — Cursor/Codex/Claude trust
  trust_all_wasteos_worktrees.sh

================================================================================
PART 2 — PRICE-LIST STEERING REFERENCE (full sources)
================================================================================
HEADER

append_file "goal-loop-prompt.md" "$PL/goal-loop-prompt.md"
append_file "implementation-stages.md" "$PL/implementation-stages.md"

{
  printf '\n================================================================================\n'
  printf 'PART 3 — SHIPFEAT CORE (SKILL + README + ZSH LAUNCHER)\n'
  printf '================================================================================\n'
} >>"$BUNDLE"

append_file "shipfeat/SKILL.md" "$SHIPFEAT/SKILL.md"
append_file "shipfeat/README.md" "$SHIPFEAT/README.md"
append_file "shipfeat.zsh" "$HOME/.config/wasteos/shipfeat.zsh"

{
  printf '\n================================================================================\n'
  printf 'PART 4 — SHIPFEAT SCRIPTS (full source)\n'
  printf '================================================================================\n'
} >>"$BUNDLE"

for f in _shipfeat_lib.sh _worktree_root.sh app_url.sh build_mr_comment_prompt.sh \
  consume_mr_comment_prompt.sh dispatch_mr_comment.sh done.sh enqueue_mr_notes.sh \
  fetch_new_mr_notes.py generate_plan_from_profile.sh init_session.sh \
  install_cursor_hooks.sh log_command.sh mr_comment_ledger.py open_mr.sh \
  playwright_shipfeat_init.sh reconcile_mr_discussions.sh record_mr_open.sh repair.sh \
  require_branch_pushed.sh require_commands_logged.sh require_mr_photos_uploaded.sh \
  require_no_unresolved_discussions.sh require_review_diff.sh require_ui_review.sh \
  resolve_mr_discussion.sh review_diff.sh run-agent.sh scaffold_implementation_stages.sh \
  seed_mr_watch_state.sh shipfeat_mr_status.sh status.sh trust_all_wasteos_worktrees.sh \
  trust_worktree.sh upload_mr_screenshots.sh wait_for_backend_ready.sh watch_mr_comments.sh; do
  append_file "shipfeat/scripts/$f" "$SHIPFEAT/scripts/$f"
done

{
  printf '\n================================================================================\n'
  printf 'PART 5 — CURSOR HOOKS + TEMPLATES\n'
  printf '================================================================================\n'
} >>"$BUNDLE"

append_file "hooks/hooks.json" "$SHIPFEAT/hooks/hooks.json"
append_file "hooks/shipfeat-mr-comment-before-prompt.sh" "$SHIPFEAT/hooks/shipfeat-mr-comment-before-prompt.sh"
append_file "hooks/shipfeat-mr-comment-stop.sh" "$SHIPFEAT/hooks/shipfeat-mr-comment-stop.sh"
append_file "templates/mr-comment-response-instructions.md" "$SHIPFEAT/templates/mr-comment-response-instructions.md"
append_file "templates/shipfeat-mr-comments.mdc" "$SHIPFEAT/templates/shipfeat-mr-comments.mdc"

{
  printf '\n================================================================================\n'
  printf 'PART 6 — COMPANION SKILLS (MR photos + MR comment watch)\n'
  printf '================================================================================\n'
} >>"$BUNDLE"

append_file "skills/wasteos-mr-upload-photos/SKILL.md" "$SKILLS/wasteos-mr-upload-photos/SKILL.md"
append_file "skills/wasteos-mr-comment-watch/SKILL.md" "$SKILLS/wasteos-mr-comment-watch/SKILL.md"

{
  printf '\n================================================================================\n'
  printf 'PART 7 — code-review-standard.md (full)\n'
  printf '================================================================================\n'
} >>"$BUNDLE"

append_file "code-review-standard.md" "$HOME/.config/wasteos/code-review-standard.md"

lines=$(wc -l <"$BUNDLE" | tr -d ' ')
{
  printf '\n================================================================================\n'
  printf 'END OF BUNDLE — %s lines total\n' "$lines"
  printf '================================================================================\n'
} >>"$BUNDLE"

echo "Wrote $BUNDLE ($lines lines, $(du -h "$BUNDLE" | awk '{print $1}'))"
