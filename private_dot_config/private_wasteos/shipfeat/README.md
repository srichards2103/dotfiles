# WasteOS shipfeat (`~/.config/wasteos/shipfeat`)

End-to-end feature delivery: implement → drst → pytest → GitLab MR → UI screenshots → **MR comment feedback loop**.

Entry from `shipfeat.zsh`:

| Command | Purpose |
|---------|---------|
| `shipfeat <branch> <agent> [context]` | Launch tmux + agent + MR watcher |
| `shipfeat status` | Session, MR, watcher, plan gates (from feature worktree) |
| `shipfeat done` | Exit 0 only when completion gates pass |
| `shipfeat repair` | Fix session/MR/hooks after Cursor-only start |
| `shipfeat review-diff` | Second-pass diff review (Tier M/L) |

| Doc | Purpose |
|-----|---------|
| [SKILL.md](./SKILL.md) | Full phase workflow (canonical for all agents) |
| [../skills/wasteos-mr-comment-watch/SKILL.md](../skills/wasteos-mr-comment-watch/SKILL.md) | MR watcher + push-before-resolve |
| [../skills/wasteos-mr-upload-photos/SKILL.md](../skills/wasteos-mr-upload-photos/SKILL.md) | Screenshot upload |

Skills are symlinked into `~/.cursor/skills`, `~/.codex/skills`, and `~/.claude/skills` when you run `shipfeat`.

## Layout

```
shipfeat/
├── SKILL.md                 # Main workflow
├── README.md                # This file
├── hooks/                   # Cursor hooks (symlinked into worktree .cursor/)
├── templates/
│   ├── feature-profile.example.json
│   ├── ui-review.md
│   ├── plan-sections/              # Scenario-specific plan blocks
│   ├── mr-comment-response-instructions.md
│   └── shipfeat-mr-comments.mdc
└── scripts/
    ├── generate_plan_from_profile.sh / scaffold_implementation_stages.sh
    ├── status.sh / done.sh / repair.sh / review_diff.sh
    ├── log_command.sh / require_commands_logged.sh
    ├── mr_comment_ledger.py + enqueue/build/reconcile MR comment scripts
    ├── shipfeat_mr_status.sh
    ├── require_no_unresolved_discussions.sh
    ├── require_ui_review.sh
    ├── init_session.sh
    ├── open_mr.sh / record_mr_open.sh   # open_mr fails if MR not recorded
    ├── watch_mr_comments.sh / dispatch_mr_comment.sh / fetch_new_mr_notes.py
    ├── require_branch_pushed.sh
    ├── resolve_mr_discussion.sh
    ├── consume_mr_comment_prompt.sh
    ├── install_cursor_hooks.sh
    ├── upload_mr_screenshots.sh       # marker includes commit_sha
    └── run-agent.sh
```

## Agents

| Agent | Started by | MR comment delivery |
|-------|------------|---------------------|
| `codex` | `run-agent.sh` → tmux pane | `tmux send-keys` + pending file |
| `claude` | same | same |
| `agent` / `cursor` | same or Cursor Composer | Cursor hooks + rule, or tmux if `dispatch_mode` overridden |

**All agents** must run `require_branch_pushed.sh` before resolving MR threads or calling `consume_mr_comment_prompt.sh`.

## Worktree artifacts (`.shipfeat/`)

Written under the feature worktree (not all committed):

| File | Purpose |
|------|---------|
| `session.json` | Branch, MR IID, agent, dispatch mode |
| `pending-mr-comment-prompt.md` | Active MR comment batch for the agent |
| `mr-comment-ready.json` | Queue signal |
| `feature-profile.json` | Tier, change_types, required gates (machine-readable) |
| `plan.md` | Generated from profile + templates — **should not be on the MR** |
| `ui-review.md` | Playwright review checklist (required for frontend) |
| `human-blocked-discussions.json` | Discussion IDs left open intentionally |
| `summary.md` | Ship summary |
| `screenshots/` | Playwright captures |

## Credentials

`~/.config/wasteos/shipfeat.env` — `SHIPFEAT_APP_EMAIL`, `SHIPFEAT_APP_PASSWORD`, optional `SHIPFEAT_APP_HOST`.

## Health checks (worktree)

After `db_deploy_and_restore_fast.sh`, Phase 3 uses:

```bash
"${SHIPFEAT_HOME}/scripts/wait_for_backend_ready.sh"
```

| Check | URL | Success |
|-------|-----|---------|
| Readiness (required) | `http://127.0.0.1:${BACKEND_PORT}/api/common/readyz/` | `200` + body `READY` |
| Liveness (optional) | `http://127.0.0.1:${BACKEND_PORT}/api/common/healthz/` | `200` + body `OK` |

**Do not use** `/readyz/` at the backend host root — Django only exposes readiness at **`/api/common/readyz/`** (see `backend/common/urls.py`, `deploy/do_deploy.sh`).

UI / Playwright: `app_url.sh` prints `http://${SHIPFEAT_APP_HOST}:${NGINX_PORT}/` so login hits nginx (API + frontend), not the raw frontend dev port alone.
