---
name: wasteos-mr-upload-photos
description: Upload PNG/JPEG/WebP screenshots to a GitLab merge request as an MR note (comment) with inline images. Use after UI work, shipfeat Phase 6, or whenever the user asks to attach photos to an MR.
---

# Upload photos to a GitLab MR note

Agents **must** use this skill whenever UI screenshots belong on an MR. Do not paste image paths in chat only — upload them to GitLab with the script below.

## When this is mandatory

- Any feature that changed frontend UI (pages, modals, forms, tables).
- End of `wasteos-ship-feat` Phase 6 (always, if Phase 6 ran).
- User asks to "add screenshots", "attach photos", or "show UI on the MR".

Backend-only changes with no UI still skip screenshots, but if you captured any UI for verification, upload them anyway.

## Prerequisites

- On the feature branch with an open MR (`glab mr view` works).
- Run from the **feature worktree root** (directory containing `.worktree.env`).
- `glab` authenticated for the project.
- Images saved locally (`.shipfeat/screenshots/` during shipfeat).

## Upload (required command)

```bash
export SHIPFEAT_HOME="${SHIPFEAT_HOME:-$HOME/.config/wasteos/shipfeat}"
branch="$(git branch --show-current)"

"${SHIPFEAT_HOME}/scripts/upload_mr_screenshots.sh" "$branch" .shipfeat/screenshots
```

Single file:

```bash
"${SHIPFEAT_HOME}/scripts/upload_mr_screenshots.sh" "$branch" .shipfeat/screenshots/billing-list.png
```

Custom note title (optional third argument):

```bash
"${SHIPFEAT_HOME}/scripts/upload_mr_screenshots.sh" "$branch" .shipfeat/screenshots "UI verification — billing batch"
```

The script:

1. POSTs each image via GitLab `projects/:id/uploads`.
2. Builds one MR note with inline `![...](uploads/...)` markdown.
3. Posts the note with `glab mr note`.
4. Writes `.shipfeat/mr-photos-uploaded.json` with `branch`, `commit_sha`, `uploaded_at`, `files`, optional `routes_reviewed`.

`require_mr_photos_uploaded.sh` fails if frontend changed after the marker commit.

**Do not** hand-roll `glab api` upload calls unless this script cannot run — prefer fixing the script.

## Verify before claiming done

```bash
test -f .shipfeat/mr-photos-uploaded.json && echo "MR photos uploaded"
glab mr view "$(git branch --show-current)" --comments | head -20
```

If upload failed, fix and re-run. **Do not** mark shipfeat or the task complete until `upload_mr_screenshots.sh` exits 0 and the marker file exists.

## Screenshot capture (shipfeat / Playwright)

Before upload, capture UI with **playwright-cli** (see `.agents/skills/playwright-cli/SKILL.md` in the worktree):

```bash
source ~/.config/wasteos/shipfeat.env 2>/dev/null || true
app_url="$("${SHIPFEAT_HOME}/scripts/app_url.sh")"
mkdir -p .shipfeat/screenshots
"${SHIPFEAT_HOME}/scripts/playwright_shipfeat_init.sh" "$app_url"
# login, navigate, screenshot each changed surface (viewport must stay 1920x1080), close
```

Save descriptive filenames: `invoice-batch-list.png`, `modal-create-error.png`.

## Failure handling

| Problem | Action |
|---------|--------|
| No MR for branch | Run `open_mr.sh` first, then re-upload |
| Empty screenshot dir | Capture UI first; if truly no UI, document in `.shipfeat/summary.md` why |
| `glab` auth error | Stop; tell user to fix `glab auth` |
| Upload API error | Retry once; if still failing, stop and report |

## Completion checklist

```text
[ ] At least one screenshot per changed UI surface (or documented N/A)
[ ] upload_mr_screenshots.sh exited 0
[ ] .shipfeat/mr-photos-uploaded.json exists
[ ] MR note visible on GitLab with inline images
```
