import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

PATTERN = re.compile(r"^(\d{14})_([A-Za-z0-9_]+)\.sql$")
DEFAULT_PROJECT_REF = "tgeezbwbrovfyjbeykrj"


def npx_command():
    return "npx.cmd" if os.name == "nt" else "npx"


def fetch_remote_history(root: Path, project_ref: str):
    sql = (
        "select version,name,statements "
        "from supabase_migrations.schema_migrations order by version"
    )
    cmd = [
        npx_command(), "--yes", "supabase@latest",
        "db", "query", "--linked", "--project-ref", project_ref,
        "--output-format", "json", sql,
    ]
    proc = subprocess.run(cmd, cwd=root, capture_output=True)
    stdout = proc.stdout.decode("utf-8", errors="replace")
    stderr = proc.stderr.decode("utf-8", errors="replace")
    if proc.returncode != 0:
        print(stdout, file=sys.stderr)
        print(stderr, file=sys.stderr)
        raise RuntimeError("failed to read production migration history")
    return json.loads(stdout)
def scan_local(root: Path):
    rows = {}
    errors = []
    for path in sorted((root / "supabase" / "migrations").glob("*.sql")):
        match = PATTERN.match(path.name)
        if not match:
            errors.append(f"invalid migration filename: {path.name}")
            continue
        version, name = match.groups()
        if version in rows:
            errors.append(f"duplicate local migration version: {version}")
            continue
        rows[version] = {"version": version, "name": name, "path": path}
    return rows, errors


def reconstruct_sql(item):
    parts = []
    for statement in item.get("statements") or []:
        text = statement.rstrip()
        parts.append(text if text.endswith(";") else text + ";")
    return "\n\n".join(parts).rstrip() + "\n"


def compare(local, remote):
    remote_map = {str(item["version"]): item for item in remote}
    remote_versions = set(remote_map)
    local_versions = set(local)
    remote_only = sorted(remote_versions - local_versions)
    local_only = sorted(local_versions - remote_versions)
    mismatched_names = []
    for version in sorted(remote_versions & local_versions):
        if local[version]["name"] != remote_map[version]["name"]:
            mismatched_names.append(
                (
                    version,
                    local[version]["name"],
                    remote_map[version]["name"],
                )
            )

    latest_remote = max(remote_versions) if remote_versions else ""
    historical_local_only = [v for v in local_only if v <= latest_remote]
    future_local_only = [v for v in local_only if v > latest_remote]
    return {
        "remote_map": remote_map,
        "remote_only": remote_only,
        "historical_local_only": historical_local_only,
        "future_local_only": future_local_only,
        "mismatched_names": mismatched_names,
        "latest_remote": latest_remote,
    }


def print_report(result, local):
    print(
        "production migration parity: "
        f"remote_only={len(result['remote_only'])} "
        f"historical_local_only={len(result['historical_local_only'])} "
        f"future_local_only={len(result['future_local_only'])} "
        f"name_mismatch={len(result['mismatched_names'])}"
    )
    if result["remote_only"]:
        print("remote-only:")
        for version in result["remote_only"]:
            item = result["remote_map"][version]
            print(f"  {version}_{item['name']}.sql")
    if result["historical_local_only"]:
        print("historical local-only:")
        for version in result["historical_local_only"]:
            print(f"  {local[version]['path'].name}")
    if result["future_local_only"]:
        print("pending new migrations:")
        for version in result["future_local_only"]:
            print(f"  {local[version]['path'].name}")
    if result["mismatched_names"]:
        print("version/name mismatch:")
        for version, local_name, remote_name in result["mismatched_names"]:
            print(f"  {version}: local={local_name} remote={remote_name}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=None)
    parser.add_argument("--project-ref", default=DEFAULT_PROJECT_REF)
    parser.add_argument("--repair-from-production", action="store_true")
    args = parser.parse_args()
    root = Path(args.root).resolve() if args.root else Path(__file__).resolve().parents[1]
    local, errors = scan_local(root)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    remote = fetch_remote_history(root, args.project_ref)
    result = compare(local, remote)
    print_report(result, local)

    if result["mismatched_names"] or result["historical_local_only"]:
        print(
            "BLOCKED: historical local migration conflicts with Production.",
            file=sys.stderr,
        )
        return 2

    if result["remote_only"]:
        if not args.repair_from_production:
            print(
                "BLOCKED: Production has migrations missing locally. "
                "Run with --repair-from-production, commit the recovered files, "
                "then deploy again.",
                file=sys.stderr,
            )
            return 3
        for version in result["remote_only"]:
            item = result["remote_map"][version]
            target = (
                root / "supabase" / "migrations"
                / f"{version}_{item['name']}.sql"
            )
            target.write_text(reconstruct_sql(item), encoding="utf-8")
            print(f"recovered {target.name}")
        print("RECOVERED: commit recovered migrations before any Production push.")
        return 4

    print(
        "PRODUCTION HISTORY CHECK: OK "
        f"latest_remote={result['latest_remote']} "
        f"pending_new={len(result['future_local_only'])}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
