const fs=require('fs'),assert=require('assert/strict');
const {chromium}=require('C:/Users/acer/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
(async()=>{const browser=await chromium.launch({channel:'msedge',headless:true});try{
 const page=await browser.newPage({viewport:{width:390,height:844}});
 const source=fs.readFileSync('app.js','utf8');
 const guard=source.slice(source.indexOf('function ncdEntryGuardV2122('),source.indexOf('function ensureBpRepeatUiV2123('));
 const sync=source.slice(source.indexOf('function syncNcdSubmitState('),source.indexOf('async function hydratePreviousScreening('));
 await page.setContent('<form id="ncd-form"><input name="weight_kg" value="53"><input name="height_cm" value="220"><input name="waist_cm" value="80"><input name="sbp" value="120"><input name="dbp" value="80"><input name="pulse" value="72"><input name="glucose_mg_dl" value="90"><input name="glucose_type" type="radio" value="fasting" checked><button id="ncd-submit" type="button">บันทึก</button><p id="ncd-submit-hint"></p><output id="saved">0</output></form>');
 await page.addScriptTag({content:`const $=s=>document.querySelector(s);const selectedHealthPerson={previous_height_cm:220};const ncdRequiredComplete=()=>true;const bpRepeatStateV2123=f=>({effectiveSbp:Number(f.elements.sbp.value),effectiveDbp:Number(f.elements.dbp.value),anyGrade3:false});${guard}\n${sync}\nsyncNcdSubmitState();$('#ncd-submit').onclick=()=>{if(confirmNcdEntryGuardV2122($('#ncd-form'),selectedHealthPerson))$('#saved').textContent='1';};`});
 assert((await page.locator('#ncd-submit-hint').textContent()).includes('ส่วนสูง 220'));
 page.once('dialog',async d=>{assert(d.message().includes('ส่วนสูง 220'));await d.dismiss();});await page.locator('button').click();assert.equal(await page.locator('#saved').textContent(),'0');
 page.once('dialog',d=>d.accept());await page.locator('button').click();assert.equal(await page.locator('#saved').textContent(),'1');
 console.log('Browser live warning, cancel prevents save, confirm allows save passed');
 }finally{await browser.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
