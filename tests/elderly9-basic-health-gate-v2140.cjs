const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const ui = fs.readFileSync(path.join(root, 'phc-five-features-v190.mjs'), 'utf8');
const sql = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20261006144644_elderly9_basic_health_gate_v2140.sql'), 'utf8');

assert.match(ui, /elderlyBothDmHtV2140\(s\)/, 'UI must distinguish people with both DM and HT');
assert.match(ui, /save_elderly9_basic_health_v2140/, 'UI must save a same-session basic health exam');
assert.match(ui, /if\(bothDmHt\)await loadElderlyBasicHealthV2140/, 'both-disease route must pass the basic health gate');
assert.match(ui, /else await loadElderlyWizardV207/, 'other elderly routes must continue using the existing NCD flow');
assert.match(ui, /กรุณากรอกค่าที่วัดวันนี้ให้ครบทุกช่อง/, 'all basic measurements must be required');
assert.match(ui, /ชีพจร.*50–120/, 'pulse warning range must be visible');
assert.doesNotMatch(ui.match(/function elderlyBasicHealthFormV2140[\s\S]*?\n\}/)?.[0] || '', /glucose|น้ำตาล|smoking|บุหรี่|alcohol|สุรา/i, 'basic elderly exam must not add unrelated NCD fields');

assert.match(sql, /enable row level security/i, 'new table must enable RLS');
assert.match(sql, /revoke insert, update, delete .* from authenticated/i, 'browser must not write the table directly');
assert.match(sql, /security definer[\s\S]*set search_path = ''/i, 'write RPC must use a fixed search path');
assert.match(sql, /coalesce\(person\.has_dm,false\) and coalesce\(person\.has_ht,false\)/i, 'RPC must verify both disease flags');
assert.match(sql, /ELDERLY_BASIC_HEALTH_REQUIRED_FIRST/, 'database trigger must block bypassing the gate');
assert.match(sql, /measured_on=s\.screening_date/i, 'gate must require the same screening date');
assert.match(sql, /screening_date>=date '2026-10-06'/i, 'historical completed screenings must remain editable');

console.log('elderly9 basic-health gate v2140: ok');
