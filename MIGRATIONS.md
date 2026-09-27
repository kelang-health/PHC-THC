# Production Migration Policy

GitHub `kelang-health/PHC-THC` branch `main` is the migration source of truth for OSM-PHC Cloud.

## Rules

1. Existing files in `supabase/migrations` are immutable after commit.
2. Create schema changes only as a new timestamped migration.
3. A Production migration must be committed and pushed to `main` before it is applied.
4. Do not use a raw `supabase db push` for Production. Use `tools/push-production-migrations.ps1`.
5. The deploy wrapper blocks when the Git tree is dirty, HEAD differs from `origin/main`, Production has Remote-only migrations, a historical Local-only migration is inserted before the Production tip, or a migration version/name differs.

## Normal change

1. Create a new migration with the Supabase CLI.
2. Review and test the SQL.
3. Refresh the baseline: `py tools/check_migration_integrity.py --write-baseline`.
4. Run: `py tools/check_migration_integrity.py`.
5. Commit and push the migration plus baseline to `main`.
6. Apply with: `powershell -ExecutionPolicy Bypass -File tools/push-production-migrations.ps1`.
7. The wrapper performs Production history pre-check, dry-run, push, and post-check.

## Emergency Production DDL

If a migration is applied directly through MCP or another emergency path, do not run another Production push first.

Run: `py tools/production_migration_sync.py --repair-from-production`.

This recovers Remote-only migration history into files. Review the recovered SQL, refresh the baseline, commit/push it to `main`, and only then resume the normal deploy path.
