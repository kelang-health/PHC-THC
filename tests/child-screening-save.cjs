const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { chromium } = require('C:/Users/acer/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');

const moduleSource = fs.readFileSync(path.join(__dirname, '..', 'phc-five-features-v190.mjs'), 'utf8')
  .replace(/^import[^\n]*\n/, '').replaceAll('export ', '');

(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    await page.setContent('<meta name="phc-release" content="2.0.199">');
    await page.addScriptTag({ content: `
      (() => {
        ${moduleSource}
        const writes = [];
        let rejectDevelopment = true;
        let resolveGrowth;
        supabase = {
          from() {
            const query = { select: () => query, eq: () => query,
              maybeSingle: async () => ({data: {enabled: true}}) };
            return query;
          },
          async rpc(name, args) {
            if (name === 'screening_plan_for_person_v2023') {
              return {data: {source_pcucode: '06116', source_pid: 1, route: args.p_source_pid === 2
                ? 'school_6_14' : 'child_0_5', age_years: 4, age_months: 57, dspm_target_months: 60}};
            }
            if (name === 'growth_timeline_v204') return {data: []};
            writes.push({name, args});
            if (name === 'ensure_screening_session_v2023') return {data: {session_id: 'test-session'}};
            if (name === 'save_growth_screening_v190') {
              return new Promise(resolve => { resolveGrowth = () => resolve({data: {ok: true}}); });
            }
            if (name === 'save_child_development_v190') {
              if (rejectDevelopment) {
                rejectDevelopment = false;
                return {error: {message: 'ลองใหม่'}};
              }
              return {data: {ok: true, overall_label: 'ควรประเมินเพิ่มเติม',
                overall_status: 'needs_further_assessment'}};
            }
            throw Error('Unexpected RPC ' + name);
          },
        };
        injectStyle();
        window.screening = {
          open: pid => openAgeScreening('06116', pid, 'เด็กทดสอบ'),
          writes, releaseGrowth: () => resolveGrowth(),
        };
      })();
    ` });

    await page.evaluate(() => screening.open(1));
    const save = page.locator('[data-child-save]');
    const error = page.locator('[data-dev-error]');
    const weight = page.locator('[data-growth-weight]');
    const height = page.locator('[data-growth-height]');
    assert.equal(await page.locator('[data-growth-save]').count(), 0);
    await save.click();
    assert.match(await error.textContent(), /กรุณากรอกน้ำหนัก/);
    await weight.fill('15.2');
    await height.fill('29');
    await save.click();
    assert.match(await error.textContent(), /กรุณากรอกส่วนสูง/);
    await height.fill('101.5');
    await save.click();
    assert.match(await error.textContent(), /ประเมินพัฒนาการให้ครบ 5 ด้าน/);
    assert.equal(await page.evaluate(() => screening.writes.length), 0);

    await page.click('[data-all-normal]');
    const motor = page.locator('[data-dev-domain="gross_motor"]');
    await motor.locator('[data-state="observation"]').click();
    await motor.locator('input').first().check();
    await save.click();
    await page.waitForFunction(() => screening.writes.some(row => row.name === 'save_growth_screening_v190'));
    assert.equal(await save.isDisabled(), true);
    await save.evaluate(button => button.click());
    await page.evaluate(() => screening.releaseGrowth());
    await page.waitForFunction(() => document.querySelector('[data-dev-error]').textContent.includes('บันทึกน้ำหนักและส่วนสูงแล้ว'));
    assert.equal(await page.locator('.phc190-overlay').count(), 1);
    assert.equal(await weight.getAttribute('readonly'), '');
    assert.equal(await height.inputValue(), '101.5');
    await save.click();
    await page.waitForSelector('.phc190-overlay', { state: 'detached' });

    const writes = await page.evaluate(() => screening.writes);
    assert.deepEqual(writes.map(row => row.name), [
      'ensure_screening_session_v2023', 'save_growth_screening_v190',
      'save_child_development_v190', 'save_child_development_v190',
    ]);
    assert.deepEqual(writes[1].args, { p_session_id: 'test-session', p_weight_kg: 15.2, p_height_cm: 101.5 });
    assert.equal(Object.keys(writes[3].args.p_domains).length, 5);
    assert.equal(writes[3].args.p_domains.gross_motor, 'observation');
    assert.match(writes[3].args.p_note, /การเคลื่อนไหว/);
    assert.match(await page.locator('.phc190-toast').textContent(), /บันทึกน้ำหนัก ส่วนสูง และพัฒนาการแล้ว/);

    await page.evaluate(() => screening.open(2));
    assert.equal(await page.locator('[data-growth-save]').isVisible(), true);
    assert.equal(await page.locator('[data-child-save]').count(), 0);
    console.log('PASS: child screening completeness, double-click, partial failure, development-only retry, auto-close, and school growth');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
