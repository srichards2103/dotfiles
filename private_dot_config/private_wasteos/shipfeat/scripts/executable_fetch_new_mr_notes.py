#!/usr/bin/env python3
"""Return new human MR notes since last_note_id (stdout: JSON array)."""

from __future__ import annotations

import json
import os
import subprocess
import sys


def run(cmd: list[str]) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def glab_user() -> str | None:
    try:
        out = run(["glab", "api", "user"])
        return json.loads(out).get("username")
    except SystemExit:
        return None


def is_our_upload(body: str) -> bool:
    markers = (
        "wasteos-mr-upload-photos",
        "wasteos-ship-feat",
        "UI verification screenshots",
        "Automated captures from",
        "Posted via `wasteos-mr-upload-photos`",
    )
    return any(m in body for m in markers)


def load_session(session_path: str) -> dict:
    if not os.path.isfile(session_path):
        return {}
    with open(session_path, encoding="utf-8") as f:
        return json.load(f)


def main() -> None:
    if len(sys.argv) != 4:
        print(
            "Usage: fetch_new_mr_notes.py <mr_iid> <state_path> <session_path>",
            file=sys.stderr,
        )
        sys.exit(1)

    mr_iid = sys.argv[1]
    state_path = sys.argv[2]
    session_path = sys.argv[3]
    session = load_session(session_path)
    include_own = bool(session.get("include_own_mr_notes"))

    last_id = 0
    if os.path.isfile(state_path):
        with open(state_path, encoding="utf-8") as f:
            last_id = int(json.load(f).get("last_note_id", 0))

    notes_raw = run(
        [
            "glab",
            "api",
            f"projects/:id/merge_requests/{mr_iid}/notes?per_page=100&sort=asc&order_by=created_at",
        ]
    )
    notes = json.loads(notes_raw)

    note_to_discussion: dict[int, str] = {}
    try:
        disc_raw = run(
            [
                "glab",
                "api",
                f"projects/:id/merge_requests/{mr_iid}/discussions?per_page=100",
            ]
        )
        for disc in json.loads(disc_raw):
            disc_id = disc.get("id")
            if not disc_id:
                continue
            for disc_note in disc.get("notes") or []:
                note_to_discussion[int(disc_note["id"])] = disc_id
    except SystemExit:
        pass

    me = glab_user()

    new_notes = []
    max_id = last_id
    for note in notes:
        nid = int(note["id"])
        max_id = max(max_id, nid)
        if nid <= last_id:
            continue
        if note.get("system"):
            continue
        body = (note.get("body") or "").strip()
        if not body:
            continue
        if is_our_upload(body):
            continue
        author = note.get("author") or {}
        if me and author.get("username") == me and not include_own:
            continue
        entry = {
            "id": nid,
            "author": author.get("username") or author.get("name") or "unknown",
            "body": body,
            "created_at": note.get("created_at"),
        }
        discussion_id = note_to_discussion.get(nid)
        if discussion_id:
            entry["discussion_id"] = discussion_id
        new_notes.append(entry)

    if new_notes or max_id > last_id:
        state = {}
        if os.path.isfile(state_path):
            with open(state_path, encoding="utf-8") as f:
                state = json.load(f)
        state["last_note_id"] = max_id
        with open(state_path, "w", encoding="utf-8") as f:
            json.dump(state, f, indent=2)
            f.write("\n")

    json.dump(new_notes, sys.stdout)


if __name__ == "__main__":
    main()
