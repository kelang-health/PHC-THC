import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

PATTERN = re.compile(r"^(\d{14})_([A-Za-z0-9_]+)\.sql$")


def sha256_file(path: Path) -> str:
    data = path.read_bytes()
    # Git may check out text as CRLF on Windows and LF on Linux.
    # Migration integrity is content-based, not platform-line-ending-based.
    data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return hashlib.sha256(data).hexdigest()


def scan_migrations(root: Path):
    migrations_dir = root / "supabase" / "migrations"
    rows = []
    errors = []
    seen = {}
    for path in sorted(migrations_dir.glob("*.sql")):
        match = PATTERN.match(path.name)
        if not match:
            errors.append(f"invalid migration filename: {path.name}")
            continue
        version, name = match.groups()
        if version in seen:
            errors.append(
                f"duplicate migration version {version}: "
                f"{seen[version]} and {path.name}"
            )
        seen[version] = path.name
        rows.append(
            {
                "version": version,
                "name": name,
                "filename": path.name,
                "sha256": sha256_file(path),
            }
        )
    rows.sort(key=lambda x: x["version"])
    return rows, errors


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))
def load_baseline_from_git(root: Path, ref: str):
    if not ref or set(ref) == {"0"}:
        return None
    proc = subprocess.run(
        ["git", "show", f"{ref}:supabase/migration-baseline.json"],
        cwd=root,
        text=True,
        capture_output=True,
    )
    if proc.returncode != 0:
        return None
    return json.loads(proc.stdout)


def validate_against_previous(current_baseline, previous_baseline):
    errors = []
    if not previous_baseline:
        return errors
    prev_rows = {
        item["version"]: item
        for item in previous_baseline.get("migrations", [])
    }
    cur_rows = {
        item["version"]: item
        for item in current_baseline.get("migrations", [])
    }

    prev_schema = previous_baseline.get("schema", 1)
    cur_schema = current_baseline.get("schema", 1)
    if prev_schema != cur_schema:
        if set(prev_rows) != set(cur_rows):
            errors.append("baseline schema upgrade may not add/remove migrations")
            return errors
        for version, old in prev_rows.items():
            new = cur_rows[version]
            for key in ("version", "name", "filename"):
                if new.get(key) != old.get(key):
                    errors.append(
                        "baseline schema upgrade changed historical migration: "
                        f"{old.get('filename', version)}"
                    )
        return errors

    for version, old in prev_rows.items():
        new = cur_rows.get(version)
        if new is None:
            errors.append(f"historical migration removed: {old['filename']}")
            continue
        if new != old:
            errors.append(f"historical migration changed: {old['filename']}")

    if prev_rows:
        old_max = max(prev_rows)
        for version, item in cur_rows.items():
            if version not in prev_rows and version <= old_max:
                errors.append(
                    "new migration backfills history before/equal baseline max: "
                    f"{item['filename']} <= {old_max}"
                )
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=None)
    parser.add_argument("--base-ref", default=None)
    parser.add_argument("--write-baseline", action="store_true")
    args = parser.parse_args()
    root = Path(args.root).resolve() if args.root else Path(__file__).resolve().parents[1]
    baseline_path = root / "supabase" / "migration-baseline.json"
    rows, errors = scan_migrations(root)

    baseline = {
        "schema": 2,
        "hash_mode": "sha256_lf_normalized",
        "latest_version": rows[-1]["version"] if rows else None,
        "migration_count": len(rows),
        "migrations": rows,
    }

    if args.write_baseline:
        baseline_path.write_text(
            json.dumps(baseline, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"baseline written: {len(rows)} migrations")
        return 0

    if not baseline_path.exists():
        errors.append("missing supabase/migration-baseline.json")
        stored = None
    else:
        stored = load_json(baseline_path)
        if stored != baseline:
            errors.append("migration baseline does not match current migration files")
    if stored and args.base_ref:
        previous = load_baseline_from_git(root, args.base_ref)
        errors.extend(validate_against_previous(stored, previous))

    if errors:
        print("MIGRATION INTEGRITY: FAIL", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(
        "MIGRATION INTEGRITY: OK "
        f"count={len(rows)} latest={baseline['latest_version']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
