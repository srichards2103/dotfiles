---
name: wasteos-mr-comment-watch
description: Poll a GitLab MR for new human comments and dispatch the shipfeat agent (Cursor, Claude, Codex, or tmux) to address them — push before resolve, screenshots, GitLab replies. Started by shipfeat.
---

# MR comment watcher (shipfeat)

`shipfeat` starts `watch_mr_comments.sh` in a tmux pane. It polls GitLab (~45s), **enqueues** notes under `.shipfeat/mr-comments/queued/`, records state in `.shipfeat/mr-comment-ledger.jsonl`, **builds** `.shipfeat/pending-mr-comment-prompt.md` when new items are queued, and signals the agent. `reconcile_mr_discussions.sh` re-queues unresolved GitLab threads that were lost from the queue.

**The watcher does not fix MR feedback itself.** The agent running in the feature worktree does.

## Agent matrix

| Agent | `session.json` `dispatch_mode` | How the queue is delivered | How the agent consumes |
|-------|-------------------------------|----------------------------|-------------------------|
| **`agent`** (Cursor CLI / Composer) | `cursor` | `mr-comment-ready.json` + Cursor hooks/rule | Read pending file; hooks nudge; `consume_mr_comment_prompt.sh` when done |
| **`cursor`** | `cursor` | same as `agent` | same |
| **`claude`** | `tmux` | `tmux send-keys` to agent pane | Read pending file when nudged; poll `mr-comment-ready.json` if needed |
| **`codex`** | `tmux` | `tmux send-keys` to agent pane | same as `claude` |

`init_session.sh` sets `dispatch_mode` automatically from the agent name.

### Cursor (`agent` / `cursor`)

`install_cursor_hooks.sh` (run by `shipfeat`) installs:

1. `.cursor/rules/shipfeat-mr-comments.mdc` — while `mr-comment-ready.json` exists, read the pending prompt first.
2. `beforeSubmitPrompt` hook — injects reminder on each user message.
3. `stop` hook — `followup_message` to continue the loop.

**Requires project hooks defined** — `install_cursor_hooks.sh` writes `.cursor/hooks.json` and scripts (Cursor runs them by default when present).

### Claude / Codex (tmux pane)

The watcher still writes the same files. Dispatch sends a one-line instruction to `tmux_agent_target` (shipfeat agent pane). The agent must:

1. Open `.shipfeat/pending-mr-comment-prompt.md`.
2. Follow this skill.
3. Run `consume_mr_comment_prompt.sh` when finished.

If you run Claude/Codex **outside** shipfeat tmux (e.g. Cursor Composer on the worktree), use **`cursor`** dispatch: set `"dispatch_mode": "cursor"` in `.shipfeat/session.json` and run `install_cursor_hooks.sh`.

## Push before resolve (hard gate)

**Never resolve a GitLab thread until the branch is pushed.**

```bash
git push origin "$(git branch --show-current)"
"${SHIPFEAT_HOME:-$HOME/.config/wasteos/shipfeat}/scripts/require_branch_pushed.sh"
```

Any **tracked** change counts — including deleting `.shipfeat/plan.md` or other files on the branch. Local-only deletes without commit + push do **not** satisfy the MR.

Resolve only through:

```bash
"${SHIPFEAT_HOME}/scripts/resolve_mr_discussion.sh" <mr_iid> <discussion_id> -m "…"
```

That script refuses to resolve if `require_branch_pushed.sh` fails.

`consume_mr_comment_prompt.sh` runs `require_branch_pushed.sh`, **verifies** each discussion in the active batch is resolved on GitLab (or blocked + replied), then archives the batch. It will **not** clear the queue if any discussion is still open.

## Required behaviour when dispatched

Read `.shipfeat/pending-mr-comment-prompt.md` (full checklist in `~/.config/wasteos/shipfeat/templates/mr-comment-response-instructions.md`).

### Path A — Any branch change (code, UI, file delete, config)

1. Implement → test (if applicable) → **commit** → **push** → `require_branch_pushed.sh`
2. UI: screenshots + `upload_mr_screenshots.sh`
3. Reply on GitLab thread
4. `resolve_mr_discussion.sh` (not raw `glab … resolved=true`)

### Path B — No branch change / unclear

1. Reply with a question on GitLab
2. **Leave thread open** (no resolve, no empty push)

### Forbidden

- Resolve before push verified
- Delete tracked files without commit + push
- `consume_mr_comment_prompt.sh` while dirty or ahead of origin
- Finish without GitLab reply

## Files

| Path | Purpose |
|------|---------|
| `.shipfeat/session.json` | `branch`, `agent`, `mr_iid`, `dispatch_mode`, `tmux_agent_target`, `include_own_mr_notes` |
| `.shipfeat/mr-comments/queued/` | Per-note queue files (`000000123-note.md`) |
| `.shipfeat/mr-comment-ledger.jsonl` | Durable state per note (queued → in_progress → resolved) |
| `.shipfeat/mr-comment-active-batch.json` | Current batch `discussion_ids` for consume verification |
| `.shipfeat/pending-mr-comment-prompt.md` | Built prompt for the active batch |
| `.shipfeat/mr-comment-ready.json` | Cursor dispatch signal |
| `.shipfeat/human-blocked-discussions.json` | Discussion IDs left open intentionally (must reply) |
| `.shipfeat/mr-watch-state.json` | `last_note_id` poll cursor |
| `.shipfeat/stop-mr-watch` | Stop watcher |

Comment headers: `note <id>`, `discussion <id>` for `resolve_mr_discussion.sh`.

## Scripts (`SHIPFEAT_HOME/scripts/`)

| Script | Purpose |
|--------|---------|
| `watch_mr_comments.sh` | Poll, enqueue, build, dispatch |
| `enqueue_mr_notes.sh` | Add notes to queue + ledger |
| `build_mr_comment_prompt.sh` | Assemble pending prompt from queue |
| `reconcile_mr_discussions.sh` | Re-queue unresolved discussions |
| `require_branch_pushed.sh` | Gate: clean tree + no unpushed commits |
| `resolve_mr_discussion.sh` | Reply + resolve (after push gate) |
| `consume_mr_comment_prompt.sh` | Verify discussions + clear batch |
| `install_cursor_hooks.sh` | Cursor hooks + rule (per worktree) |
| `seed_mr_watch_state.sh` | Ignore existing MR notes |

## Manual run

```bash
export SHIPFEAT_HOME=~/.config/wasteos/shipfeat
cd /path/to/feature-worktree
"${SHIPFEAT_HOME}/scripts/install_cursor_hooks.sh"   # Cursor only
"${SHIPFEAT_HOME}/scripts/watch_mr_comments.sh"
```

## Related

- `wasteos-ship-feat` — Phase 5b
- `wasteos-mr-upload-photos` — screenshot upload
