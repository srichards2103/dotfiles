#!/usr/bin/env bash
# Build .shipfeat/plan.md from feature-profile.json + scenario templates.
set -euo pipefail

# shellcheck source=_worktree_root.sh
source "$(dirname "$0")/_worktree_root.sh"

repo_root="$(shipfeat_worktree_root)"
cd "$repo_root"

profile="${repo_root}/.shipfeat/feature-profile.json"
tooling="$(shipfeat_tooling_root)"
sections_dir="${tooling}/templates/plan-sections"

if [[ ! -f "$profile" ]]; then
  echo "generate_plan_from_profile: missing ${profile}" >&2
  echo "Create it from: ${tooling}/templates/feature-profile.example.json" >&2
  exit 1
fi

python3 - "$profile" "$sections_dir" "${repo_root}/.shipfeat/plan.md" <<'PY'
import json
import sys
from pathlib import Path

profile_path, sections_dir, out_path = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
profile = json.loads(profile_path.read_text(encoding="utf-8"))

tier = profile.get("tier", "M")
change_types = profile.get("change_types") or []
if not change_types:
    raise SystemExit("feature-profile.json: change_types must be non-empty")

gates = []
if profile.get("requires_db_restore"):
    gates.append("db restore (drst)")
if profile.get("requires_frontend_build"):
    gates.append("frontend build/lint")
if profile.get("requires_playwright_review"):
    gates.append("Playwright UI review")
if profile.get("requires_openapi_regen"):
    gates.append("OpenAPI regen")
if "backend_api" in change_types or profile.get("requires_db_restore"):
    gates.append("pytest")
gates.append("MR + comment loop")
if profile.get("requires_playwright_review") or "frontend_ui" in change_types:
    gates.append("screenshots on MR")
if profile.get("requires_external_review"):
    gates.append("external review")
if tier == "L":
    gates.append("docs/specs/<feature>/implementation-stages.md")

order = [
    "backend_api",
    "model_migration",
    "permissions",
    "etl_import",
    "billing_or_pricing",
    "async_worker",
    "frontend_ui",
    "infra_ci",
]
seen = set()
parts = [
    "# Shipfeat Plan\n",
    "\n## Feature profile\n\n",
    f"Tier: {tier}\n",
    f"Change types: {', '.join(change_types)}\n",
    f"Required gates: {', '.join(gates) or 'none'}\n",
]
if tier == "L":
    parts.append(
        "\nTier L: run scaffold_implementation_stages.sh <feature-slug> then maintain "
        "`docs/specs/<feature>/implementation-stages.md` (committed).\n"
    )
parts.append("\n## Tasks\n\n")

for key in order + [t for t in change_types if t not in order]:
    if key not in change_types or key in seen:
        continue
    seen.add(key)
    section = sections_dir / f"{key}.md"
    if section.is_file():
        parts.append(section.read_text(encoding="utf-8"))
        if not parts[-1].endswith("\n"):
            parts.append("\n")

review = sections_dir / "review_mr.md"
if review.is_file():
    parts.append(review.read_text(encoding="utf-8"))

out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text("".join(parts), encoding="utf-8")
print(f"generate_plan_from_profile: wrote {out_path}")

if tier == "L":
    import subprocess
    slug = profile.get("feature_slug")
    if not slug:
        repo = out_path.parent.parent
        branch = subprocess.check_output(
            ["git", "-C", str(repo), "branch", "--show-current"],
            text=True,
        ).strip()
        slug = branch.replace("feature/", "").split("/")[-1] or "feature"
    scaffold = Path(sys.argv[2]).parent.parent / "scripts" / "scaffold_implementation_stages.sh"
    repo = out_path.parent.parent
    if scaffold.is_file():
        subprocess.run([str(scaffold), slug], cwd=repo, check=False)
PY
