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
assert.doesNotMatch(c, /\b(?:DROP|CREATE|TRUNCATE|UPDATE|INSERT|DELETE)\b/i);
assert.doesNotMatch(c, /\b(?:GRANT|REVOKE)\b[\s\S]*?\bON\s+TABLE\s+public\./i);
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
    const grant = new RegExp('GRANT\\s+[\\s\\S]*?\\bON\\s+(?:TABLE\\s+)?public\\."?' + name + '"?\\s+TO\\s+(?:authenticated|service_role|anon)', 'i').test(clean);
    // Explicit server-only classification must be reviewed separately; do not auto-grant sensitive tables.
    const serverOnly = new RegExp('REVOKE\\s+ALL\\s+ON\\s+(?:TABLE\\s+)?public\\."?' + name + '"?\\s+FROM\\s+(?:anon|PUBLIC)', 'i').test(clean);
    if (!rls || (!grant && !serverOnly)) missing.push({table, rls, grant, serverOnly});
  }
  return missing;
};
// Unit fixtures test both "allowed, scoped grant" and "missing grant" detection.
assert.deepEqual(evaluateMigration('CREATE TABLE public.test_scoped (id integer); ALTER TABLE public.test_scoped ENABLE ROW LEVEL SECURITY; GRANT SELECT ON TABLE public.test_scoped TO authenticated;'), []);
assert.equal(evaluateMigration('CREATE TABLE public.test_missing (id integer); ALTER TABLE public.test_missing ENABLE ROW LEVEL SECURITY;')[0].table, 'test_missing');
console.log('PASS: offline SQL candidate scope, read-only catalog audit, explicit-grant unit fixtures');
if (process.argv.includes('--deployment-gate')) {
  const migrationDir = path.join(root, 'supabase/migrations');
  assert(fs.existsSync(migrationDir) && fs.statSync(migrationDir).isDirectory(), 'BLOCKED: complete historical supabase/migrations baseline is not present; do not deploy or claim db reset passed');
  const files = fs.readdirSync(migrationDir).filter(n => n.endsWith('.sql')).sort();
  assert(files.length, 'BLOCKED: empty migration baseline');
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
