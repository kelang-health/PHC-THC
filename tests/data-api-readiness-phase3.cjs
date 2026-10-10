#!/usr/bin/env node
// Phase 3 offline safety gate. NO database connections, secrets, network or deployment.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const candidatePath = path.join(root, 'database/phase2/20260924_future_public_table_defaults_candidate.sql');
const auditPath = path.join(root, 'database/phase2/data_api_readiness_audit.sql');
const candidate = fs.readFileSync(candidatePath, 'utf8');
const audit = fs.readFileSync(auditPath, 'utf8');
const executable = source => source.split(/\r?\n/).filter(line => !line.trimStart().startsWith('--')).join('\n');
const c = executable(candidate), a = executable(audit);
assert.match(c, /\bBEGIN\s*;/i);
assert.match(c, /\bCOMMIT\s*;/i);
assert.match(c, /ALTER\s+DEFAULT\s+PRIVILEGES\s+FOR\s+ROLE\s+postgres\s+IN\s+SCHEMA\s+public/i);
assert.doesNotMatch(c, /ALTER\s+DEFAULT\s+PRIVILEGES\s+FOR\s+ROLE\s+supabase_admin/i);
const candidateStatements = c.split(';').map(s => s.trim()).filter(Boolean);
assert.equal(candidateStatements.length, 3, 'Candidate may only contain BEGIN, ALTER DEFAULT PRIVILEGES, COMMIT');
assert.match(candidateStatements[0], /^BEGIN$/i);
assert.match(candidateStatements[1], /^ALTER\s+DEFAULT\s+PRIVILEGES\s+FOR\s+ROLE\s+postgres\s+IN\s+SCHEMA\s+public\s+REVOKE\s+ALL\s+PRIVILEGES\s+ON\s+TABLES\s+FROM\s+anon,\s*authenticated,\s*service_role$/i);
assert.match(candidateStatements[2], /^COMMIT$/i);
assert.match(candidate, /DO NOT RUN ON PRODUCTION/i);
const sqlStatements = a.split(';').map(s => s.trim()).filter(Boolean);
assert(sqlStatements.every(s => /^SELECT\b/i.test(s)), 'Audit file must contain SELECT statements only');
const findPublicTableCreates = source => {
  // Conservative literal-table check; dynamic SQL and unqualified table names require manual review.
  const clean = executable(source);
  return [...clean.matchAll(/\bCREATE\s+(?:UNLOGGED\s+)?TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:\"?public\"?\.)\"?([a-zA-Z_][a-zA-Z0-9_]*)\"?/gi)].map(m => m[1]);
};
const evaluateMigration = source => {
  const clean = executable(source), missing = [];
  for (const table of findPublicTableCreates(source)) {
    const name = table.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const rls = new RegExp('ALTER\\s+TABLE\\s+(?:IF\\s+EXISTS\\s+)?(?:public\\.)?"?' + name + '"?\\s+ENABLE\\s+ROW\\s+LEVEL\\s+SECURITY', 'i').test(clean);
    const grant = new RegExp('GRANT\\s+[^;]*?\\bON\\s+(?:TABLE\\s+)?public\\."?' + name + '"?\\s+TO\\s+(?:authenticated|service_role|anon)', 'i').test(clean);
    // Explicit server-only classification must be reviewed separately; do not auto-grant sensitive tables.
    const serverOnly = new RegExp('REVOKE\\s+ALL\\s+ON\\s+(?:TABLE\\s+)?public\\."?' + name + '"?\\s+FROM\\s+(?:anon|PUBLIC)', 'i').test(clean);
    if (!rls || (!grant && !serverOnly)) missing.push({table, rls, grant, serverOnly});
  }
  return missing;
};
// Unit fixtures test both "allowed, scoped grant" and "missing grant" detection.
assert.deepEqual(evaluateMigration('CREATE TABLE public.test_scoped (id integer); ALTER TABLE public.test_scoped ENABLE ROW LEVEL SECURITY; GRANT SELECT ON TABLE public.test_scoped TO authenticated;'), []);
assert.equal(evaluateMigration('CREATE TABLE public.test_missing (id integer); ALTER TABLE public.test_missing ENABLE ROW LEVEL SECURITY;')[0].table, 'test_missing');
// Multi-table fixture: a grant for one new table must not satisfy another.
assert.equal(evaluateMigration('CREATE TABLE public.first_table (id integer); CREATE TABLE public.second_table (id integer); ALTER TABLE public.first_table ENABLE ROW LEVEL SECURITY; ALTER TABLE public.second_table ENABLE ROW LEVEL SECURITY; GRANT SELECT ON TABLE public.first_table TO authenticated;').find(item => item.table === 'second_table')?.grant, false);
assert.equal(evaluateMigration('CREATE TABLE public.no_rls (id integer); GRANT SELECT ON TABLE public.no_rls TO authenticated;')[0].rls, false);
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'database/phase2/migration-history-required-20260924.json'), 'utf8'));
assert(Array.isArray(manifest.required) && manifest.required.length > 0, 'Missing recorded migration inventory');
assert.equal(new Set(manifest.required.map(item => item.version)).size, manifest.required.length, 'Duplicate baseline migration versions');
assert.equal('20260924110811_houses_removed_from_jhcis_soft_archive_v2123.sql'.match(/^([0-9]{14})_.+[.]sql$/i)?.[1], '20260924110811', 'Migration filename parser regression');
console.log('PASS: offline SQL candidate scope, read-only catalog audit, explicit-grant unit fixtures');
if (process.argv.includes('--deployment-gate')) {
  const migrationDir = path.join(root, 'supabase/migrations');
  if (!fs.existsSync(migrationDir) || !fs.statSync(migrationDir).isDirectory()) {
    // Deliberate fail-closed deployment gate. An offline fixture success never
    // establishes that production migration history can be replayed safely.
    console.error('DEPLOY BLOCKED (expected): complete, vetted supabase/migrations history is absent from this PR checkout.');
    console.error('No production website/DB failure is implied. The synthetic offline checks run separately.');
    console.error('Restore and source-vet all recorded SQL privately, sanitize data/keys, then verify full isolated replay and real-role application tests before any deploy approval.');
    process.exit(2);
  }
  const files = fs.readdirSync(migrationDir).filter(n => n.endsWith('.sql')).sort();
  assert(files.length, 'BLOCKED: empty migration baseline');
  const versions = new Map();
  for (const filename of files) {
    const version = filename.match(/^([0-9]{14})_.+[.]sql$/i)?.[1];
    assert(version, 'BLOCKED: invalid migration filename: ' + filename);
    assert(!versions.has(version), 'BLOCKED: duplicate migration version: ' + version);
    versions.set(version, filename);
  }
  const missingVersions = manifest.required.filter(item => !versions.has(item.version));
  assert.equal(missingVersions.length, 0, 'BLOCKED: missing recorded baseline versions: ' + missingVersions.map(item => item.version + '_' + item.name).join(', '));
  const recordedVersions = new Set(manifest.required.map(item => String(item.version)));
  const unexpectedVersions = [...versions.keys()].filter(version => !recordedVersions.has(version));
  assert.equal(unexpectedVersions.length, 0, 'BLOCKED: migration versions not in recorded baseline: ' + unexpectedVersions.join(', '));
  console.log('PASS: all ' + manifest.required.length + ' recorded migration versions are present in source.');
  let violations = [], checked = 0;
  for (const filename of files) {
    const source = fs.readFileSync(path.join(migrationDir, filename), 'utf8');
    checked += findPublicTableCreates(source).length;
    violations.push(...evaluateMigration(source).map(issue => ({migration:filename,...issue})));
  }
  assert.equal(violations.length, 0, 'BLOCKED: inspect public table migrations requiring explicit RLS/grants: ' + JSON.stringify(violations));
  console.log('PASS: static public table grant/RLS check across ' + files.length + ' migration files, ' + checked + ' literal public table creates.');
  console.log('NOTE: this static check is NOT an isolated database reset, API role test, or production approval.');
}
