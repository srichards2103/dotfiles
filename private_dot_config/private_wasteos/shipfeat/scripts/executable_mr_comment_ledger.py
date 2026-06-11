#!/usr/bin/env python3
"""MR comment queue, ledger, prompt build, and consume verification."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def run(cmd: list[str]) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr or result.stdout, file=sys.stderr)
        raise SystemExit(result.returncode)
    return result.stdout.strip()


def glab_user() -> str | None:
    try:
        return json.loads(run(["glab", "api", "user"])).get("username")
    except SystemExit:
        return None


def shipfeat_paths(repo_root: Path) -> dict[str, Path]:
    sf = repo_root / ".shipfeat"
    mc = sf / "mr-comments"
    return {
        "shipfeat": sf,
        "ledger": sf / "mr-comment-ledger.jsonl",
        "batch": sf / "mr-comment-active-batch.json",
        "pending": sf / "pending-mr-comment-prompt.md",
        "ready": sf / "mr-comment-ready.json",
        "blocked": sf / "human-blocked-discussions.json",
        "queued": mc / "queued",
        "in_progress": mc / "in-progress",
        "consumed": mc / "consumed",
        "blocked_dir": mc / "blocked",
    }


def ensure_dirs(paths: dict[str, Path]) -> None:
    for key in ("queued", "in_progress", "consumed", "blocked_dir"):
        paths[key].mkdir(parents=True, exist_ok=True)


def read_ledger(ledger_path: Path) -> list[dict[str, Any]]:
    if not ledger_path.is_file():
        return []
    rows: list[dict[str, Any]] = []
    for line in ledger_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            rows.append(json.loads(line))
    return rows


def write_ledger_row(ledger_path: Path, row: dict[str, Any]) -> None:
    ledger_path.parent.mkdir(parents=True, exist_ok=True)
    with ledger_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(row, separators=(",", ":")) + "\n")


def update_ledger_row(ledger_path: Path, note_id: int, **updates: Any) -> None:
    rows = read_ledger(ledger_path)
    ledger_path.write_text("", encoding="utf-8")
    for row in rows:
        if int(row["note_id"]) == note_id:
            row.update(updates)
        write_ledger_row(ledger_path, row)


def ledger_by_note_id(ledger_path: Path) -> dict[int, dict[str, Any]]:
    out: dict[int, dict[str, Any]] = {}
    for row in read_ledger(ledger_path):
        out[int(row["note_id"])] = row
    return out


def load_blocked_ids(blocked_path: Path) -> set[str]:
    if not blocked_path.is_file():
        return set()
    data = json.loads(blocked_path.read_text(encoding="utf-8"))
    if isinstance(data, list):
        return {str(x) for x in data}
    if isinstance(data, dict):
        return {str(x) for x in data.get("discussion_ids", [])}
    return set()


def note_filename(note_id: int) -> str:
    return f"{note_id:09d}-note.md"


def enqueue_notes(repo_root: Path, notes: list[dict[str, Any]]) -> int:
    paths = shipfeat_paths(repo_root)
    ensure_dirs(paths)
    by_id = ledger_by_note_id(paths["ledger"])
    enqueued = 0
    for note in notes:
        nid = int(note["id"])
        existing = by_id.get(nid)
        if existing and existing.get("status") not in ("consumed",):
            continue
        if existing and existing.get("status") == "consumed":
            continue
        fname = note_filename(nid)
        fpath = paths["queued"] / fname
        header = f"### @{note.get('author', 'unknown')} (note {nid}"
        if note.get("discussion_id"):
            header += f", discussion {note['discussion_id']}"
        header += ")\n\n"
        fpath.write_text(header + (note.get("body") or "") + "\n", encoding="utf-8")
        row = {
            "note_id": nid,
            "discussion_id": note.get("discussion_id"),
            "author": note.get("author"),
            "received_at": note.get("created_at") or utc_now(),
            "status": "queued",
            "queued_file": str(fpath.relative_to(repo_root)),
            "batch_id": None,
            "commit": None,
            "pushed": False,
            "replied": False,
            "resolved": False,
        }
        if existing:
            update_ledger_row(paths["ledger"], nid, **row)
        else:
            write_ledger_row(paths["ledger"], row)
        enqueued += 1
    return enqueued


def active_queued_rows(ledger_path: Path) -> list[dict[str, Any]]:
    active = {"queued", "in_progress", "fixed_pushed", "replied", "blocked_needs_human"}
    return [r for r in read_ledger(ledger_path) if r.get("status") in active]


def build_prompt(repo_root: Path, instructions_path: Path, session: dict[str, Any]) -> int:
    paths = shipfeat_paths(repo_root)
    ensure_dirs(paths)
    # Only build when new comments are queued — not while a batch is already in flight.
    if paths["pending"].is_file() and paths["batch"].is_file():
        return 0
    rows = [r for r in read_ledger(paths["ledger"]) if r.get("status") == "queued"]
    if not rows:
        return 0

    batch_id = utc_now().replace(":", "").replace("-", "")
    discussion_ids: list[str] = []
    parts: list[str] = []

    for row in sorted(rows, key=lambda r: int(r["note_id"])):
        nid = int(row["note_id"])
        qfile = repo_root / row["queued_file"]
        if not qfile.is_file():
            qfile = paths["queued"] / note_filename(nid)
        if qfile.is_file():
            parts.append(qfile.read_text(encoding="utf-8"))
        did = row.get("discussion_id")
        if did:
            discussion_ids.append(str(did))
        update_ledger_row(
            paths["ledger"],
            nid,
            status="in_progress",
            batch_id=batch_id,
        )
        dest = paths["in_progress"] / note_filename(nid)
        if qfile.is_file() and not dest.is_file():
            dest.write_text(qfile.read_text(encoding="utf-8"), encoding="utf-8")

    batch = {
        "batch_id": batch_id,
        "created_at": utc_now(),
        "note_ids": [int(r["note_id"]) for r in rows],
        "discussion_ids": discussion_ids,
        "mr_iid": session.get("mr_iid"),
    }
    paths["batch"].write_text(json.dumps(batch, indent=2) + "\n", encoding="utf-8")

    header = [
        "# MR review comment dispatch",
        "",
        f"Branch: **{session.get('branch', '')}**",
        f"MR: {session.get('mr_url') or ''}",
        f"MR IID: {session.get('mr_iid') or ''}",
        f"Batch: `{batch_id}`",
        "",
        "Skill: `wasteos-mr-comment-watch` — follow every hard rule below.",
        "",
    ]
    if instructions_path.is_file():
        header.append(instructions_path.read_text(encoding="utf-8"))
    else:
        header.append(f"Instructions missing: {instructions_path}")
    header.extend(["", "---", "", "## Comment batch", ""])
    paths["pending"].write_text("\n".join(header) + "\n\n".join(parts) + "\n", encoding="utf-8")

    ready = {
        "branch": session.get("branch"),
        "mr_url": session.get("mr_url"),
        "pending_file": ".shipfeat/pending-mr-comment-prompt.md",
        "batch_id": batch_id,
        "discussion_ids": discussion_ids,
        "created_at": utc_now(),
    }
    paths["ready"].write_text(json.dumps(ready, indent=2) + "\n", encoding="utf-8")
    return len(rows)


def fetch_discussions(mr_iid: str) -> list[dict[str, Any]]:
    raw = run(
        [
            "glab",
            "api",
            f"projects/:id/merge_requests/{mr_iid}/discussions?per_page=100",
        ]
    )
    return json.loads(raw)


def discussion_has_our_reply(discussion: dict[str, Any], me: str | None) -> bool:
    if not me:
        return False
    for note in discussion.get("notes") or []:
        author = (note.get("author") or {}).get("username")
        if author == me and not note.get("system"):
            return True
    return False


def verify_batch(repo_root: Path, mr_iid: str) -> tuple[bool, list[str]]:
    paths = shipfeat_paths(repo_root)
    if not paths["batch"].is_file():
        return False, ["no active batch (.shipfeat/mr-comment-active-batch.json)"]
    batch = json.loads(paths["batch"].read_text(encoding="utf-8"))
    discussion_ids = batch.get("discussion_ids") or []
    if not discussion_ids:
        note_ids = batch.get("note_ids") or []
        if note_ids:
            return True, []
        return False, ["batch has no discussion_ids or note_ids"]

    blocked = load_blocked_ids(paths["blocked"])
    me = glab_user()
    disc_by_id = {d["id"]: d for d in fetch_discussions(mr_iid)}
    errors: list[str] = []

    for did in discussion_ids:
        disc = disc_by_id.get(did)
        if not disc:
            errors.append(f"discussion {did}: not found on GitLab")
            continue
        if str(did) in blocked:
            if not discussion_has_our_reply(disc, me):
                errors.append(f"discussion {did}: blocked but no reply from you on GitLab")
            continue
        if disc.get("resolved"):
            continue
        notes = disc.get("notes") or []
        first = notes[0] if notes else {}
        preview = (first.get("body") or "")[:60]
        errors.append(
            f"discussion {did}: still unresolved — resolve via resolve_mr_discussion.sh "
            f"or add to human-blocked-discussions.json and reply ({preview!r}...)"
        )

    return (len(errors) == 0), errors


def consume_batch(repo_root: Path, mr_iid: str) -> None:
    paths = shipfeat_paths(repo_root)
    if not paths["batch"].is_file():
        raise SystemExit("consume: no active batch")

    ok, errors = verify_batch(repo_root, mr_iid)
    if not ok:
        for err in errors:
            print(err, file=sys.stderr)
        raise SystemExit(1)

    batch = json.loads(paths["batch"].read_text(encoding="utf-8"))
    stamp = utc_now().replace(":", "").replace("-", "")
    for nid in batch.get("note_ids") or []:
        src_q = paths["queued"] / note_filename(int(nid))
        src_p = paths["in_progress"] / note_filename(int(nid))
        dest = paths["consumed"] / f"{stamp}-{note_filename(int(nid))}"
        for src in (src_p, src_q):
            if src.is_file():
                dest.write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
                src.unlink()
        by_id = ledger_by_note_id(paths["ledger"])
        row = by_id.get(int(nid))
        if row:
            did = row.get("discussion_id")
            blocked = load_blocked_ids(paths["blocked"])
            status = "resolved"
            if did and str(did) in blocked:
                status = "blocked_needs_human"
            update_ledger_row(
                paths["ledger"],
                int(nid),
                status=status,
                resolved=(status == "resolved"),
                consumed_at=utc_now(),
            )

    archive = paths["shipfeat"] / "consumed"
    archive.mkdir(parents=True, exist_ok=True)
    if paths["pending"].is_file():
        dest = archive / f"mr-comment-prompt-{stamp}.md"
        dest.write_text(paths["pending"].read_text(encoding="utf-8"), encoding="utf-8")
        paths["pending"].unlink()
    paths["ready"].unlink(missing_ok=True)
    paths["batch"].unlink(missing_ok=True)


def reconcile_unresolved(repo_root: Path, mr_iid: str, session_path: Path) -> int:
    """Re-queue human unresolved discussions not in terminal ledger states."""
    paths = shipfeat_paths(repo_root)
    ensure_dirs(paths)
    session = json.loads(session_path.read_text(encoding="utf-8"))
    include_own = bool(session.get("include_own_mr_notes"))
    me = glab_user()
    by_id = ledger_by_note_id(paths["ledger"])
    terminal = {"consumed", "resolved", "blocked_needs_human"}
    requeued = 0

    for disc in fetch_discussions(mr_iid):
        if disc.get("resolved"):
            continue
        notes = disc.get("notes") or []
        if not notes:
            continue
        first = notes[0]
        if first.get("system"):
            continue
        author = (first.get("author") or {}).get("username")
        if me and author == me and not include_own:
            continue
        nid = int(first["id"])
        row = by_id.get(nid)
        if row and row.get("status") in terminal:
            continue
        body = (first.get("body") or "").strip()
        if not body:
            continue
        entry = {
            "id": nid,
            "author": author or "unknown",
            "body": body,
            "created_at": first.get("created_at"),
            "discussion_id": disc.get("id"),
        }
        if enqueue_notes(repo_root, [entry]) > 0:
            requeued += 1
    return requeued


def render_ledger_md(repo_root: Path) -> str:
    paths = shipfeat_paths(repo_root)
    rows = read_ledger(paths["ledger"])
    lines = [
        "# MR comment ledger",
        "",
        "| note_id | discussion_id | author | status | batch_id | resolved |",
        "|---------|---------------|--------|--------|----------|----------|",
    ]
    for r in rows[-50:]:
        lines.append(
            f"| {r.get('note_id')} | {r.get('discussion_id') or '—'} | "
            f"{r.get('author') or '—'} | {r.get('status')} | {r.get('batch_id') or '—'} | "
            f"{r.get('resolved')} |"
        )
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Shipfeat MR comment ledger")
    parser.add_argument("command", choices=[
        "enqueue",
        "build",
        "verify",
        "consume",
        "reconcile",
        "render-md",
        "queue-count",
        "queued-count",
    ])
    parser.add_argument("repo_root", type=Path)
    parser.add_argument("payload", nargs="?", help="JSON file or mr_iid")
    args = parser.parse_args()
    repo = args.repo_root.resolve()
    paths = shipfeat_paths(repo)

    if args.command == "enqueue":
        notes = json.loads(Path(args.payload).read_text(encoding="utf-8"))
        n = enqueue_notes(repo, notes)
        print(n)
    elif args.command == "build":
        session = json.loads((paths["shipfeat"] / "session.json").read_text(encoding="utf-8"))
        tooling = Path(os.environ.get("SHIPFEAT_HOME", Path.home() / ".config/wasteos/shipfeat"))
        instr = tooling / "templates/mr-comment-response-instructions.md"
        n = build_prompt(repo, instr, session)
        print(n)
    elif args.command == "verify":
        ok, errors = verify_batch(repo, args.payload)
        if not ok:
            for e in errors:
                print(e, file=sys.stderr)
            sys.exit(1)
        print("ok")
    elif args.command == "consume":
        consume_batch(repo, args.payload)
        print("consumed")
    elif args.command == "reconcile":
        session_path = paths["shipfeat"] / "session.json"
        n = reconcile_unresolved(repo, args.payload, session_path)
        print(n)
    elif args.command == "render-md":
        (paths["shipfeat"] / "mr-comment-ledger.md").write_text(
            render_ledger_md(repo), encoding="utf-8"
        )
        print(paths["shipfeat"] / "mr-comment-ledger.md")
    elif args.command == "queue-count":
        active = {"queued", "in_progress", "fixed_pushed", "replied"}
        n = len([r for r in read_ledger(paths["ledger"]) if r.get("status") in active])
        print(n)

    elif args.command == "queued-count":
        n = len([r for r in read_ledger(paths["ledger"]) if r.get("status") == "queued"])
        print(n)


if __name__ == "__main__":
    main()
