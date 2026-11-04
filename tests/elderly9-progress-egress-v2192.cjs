const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { chromium } = require('C:/Users/acer/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');

const source = fs.readFileSync(path.join(__dirname, '..', 'phc-five-features-v190.mjs'), 'utf8');
const wizard = source.slice(
  source.indexOf('const ELDERLY_PROGRESS_REUSE_MS'),
  source.indexOf('\nfunction ', source.indexOf('function renderElderlySummaryV207') + 1)
);

(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  try {
    const page = await browser.newPage();
    await page.setContent('<section data-route><p data-elderly-progress></p><div data-elderly-wizard></div></section>');
    await page.addScriptTag({ content: `
      const ELDER_V207 = ['cognition','mobility','nutrition','vision','hearing','depression','urinary','adl','oral']
        .map(code => ({code, label:code, icon:'', tool:''}));
      const esc = value => String(value ?? '');
      const friendlyError = error => error.message;
      const elderRiskClassV207 = row => row?.checklist?.priority === 'red' ? 'urgent' : '';
      const bindElderlyChoiceControlsV207 = () => {};
      const elderlyQuestionHtmlV207 = () => '';
      const collectElderlyAnswersV207 = () => ({ok:true, answers:{answer:true}});
      const showPhcToast = (...args) => window.toast = args;
      const root = document.querySelector('[data-route]');
      const session = {session_id:'fixture'};
      let results, reads, saves, readError, saveError, extraResult, failFinalRead;
      const totals = () => ({
        completed:results.length, remaining:9-results.length,
        observations:results.filter(row => row.status === 'observation').length
      });
      const supabase = { async rpc(name, args) {
        if (name === 'elderly9_progress_v190') {
          reads++;
          if (readError) {
            readError = false;
            return {error:new Error('fixture read failed')};
          }
          return {data:{results:structuredClone(results), ...totals()}};
        }
        if (name !== 'save_elderly9_community_v207') throw Error(name);
        saves++;
        if (saveError) {
          saveError = false;
          return {error:new Error('fixture save failed')};
        }
        const code = args.p_domain_code;
        const urgent = code === 'depression';
        const status = urgent ? 'observation' : 'normal';
        const priority = urgent ? 'red' : 'normal';
        results = results.filter(row => row.domain_code !== code);
        results.push({domain_code:code,status,checklist:{...args.p_answers,priority},note:args.p_note});
        if (extraResult && code === 'cognition') {
          results.push({domain_code:'oral',status:'normal',checklist:{},note:'concurrent'});
        }
        if (failFinalRead && code === 'oral') readError = true;
        return {data:{ok:true,domain_code:code,status,priority,urgent,...totals()}};
      }};
      ${wizard}
      window.setup = async (options = {}) => {
        results = []; reads = 0; saves = 0; readError = false;
        ({saveError, extraResult, failFinalRead} = options);
        await loadElderlyWizardV207(root,session);
      };
      window.counters = () => ({reads,saves});
    ` });
    const stats = () => page.evaluate(() => counters());
    await page.evaluate(() => setup());
    await page.locator('[data-elder-step="2"]').click();
    await page.locator('[data-elder-prev]').click();
    await page.locator('[data-elder-step="0"]').click();
    assert.deepEqual(await stats(), { reads: 1, saves: 0 });
    await page.locator('[data-elder-note]').fill('fixture note');
    await page.locator('[data-elder-next]').click();
    await page.locator('[data-elder-prev]').click();
    assert.equal(await page.locator('[data-elder-note]').inputValue(), 'fixture note');
    await page.locator('[data-elder-step="1"]').click();
    for (let index = 1; index < 9; index++) await page.locator('[data-elder-next]').click();
    assert.deepEqual(await stats(), { reads: 2, saves: 9 });
    assert.equal(await page.locator('.phc207-urgent-note').count(), 1);
    assert.match(await page.locator('[data-elderly-progress]').innerText(), /9\/9/);

    await page.evaluate(() => setup({ saveError: true, extraResult: true }));
    await page.locator('[data-elder-next]').click();
    assert.equal(await page.locator('[data-elder-error]').innerText(), 'fixture save failed');
    assert.deepEqual(await stats(), { reads: 1, saves: 1 });
    await page.locator('[data-elder-next]').click();
    assert.deepEqual(await stats(), { reads: 2, saves: 2 });

    await page.evaluate(() => setup({ failFinalRead: true }));
    for (let index = 0; index < 9; index++) await page.locator('[data-elder-next]').click();
    assert.equal(await page.locator('[data-elderly-progress]').innerText(), 'fixture read failed');
    await page.getByRole('button', { name: 'อ่านผลที่บันทึกอีกครั้ง' }).click();
    assert.deepEqual(await stats(), { reads: 3, saves: 9 });
    assert.equal(await page.locator('[data-elder-close]').count(), 1);
    console.log('Elderly wizard: 2 reads for 9 saves, revisits reuse data, stale totals refresh, errors recover, urgent summary preserved');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
