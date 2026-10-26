const fs=require('fs'),assert=require('assert/strict');
const {chromium}=require('playwright');
(async()=>{const browser=await chromium.launch({channel:'msedge',headless:true});try{
 const p=await browser.newPage({viewport:{width:390,height:844}});
 const html=fs.readFileSync('index.html','utf8'),s=fs.readFileSync('app.js','utf8');
 const form=html.match(/<form\b[^>]*id="ncd-form"[\s\S]*?<\/form>/)[0];
 await p.setContent('<meta charset="utf-8"><style>'+fs.readFileSync('style.css','utf8')+'</style>'+form);
 await p.addScriptTag({content:s.slice(s.indexOf('function syncNcdGlucoseRequirement('),s.indexOf('function ncdFirstInvalidField('))+'\nfunction bpRepeatStateV2123(){return {highFirst:false};}'});
 await p.evaluate(()=>{const f=document.querySelector('form');f.hidden=false;for(const el of f.querySelectorAll('[hidden]'))el.hidden=false;const values={screened_on:'2026-10-26',weight_kg:'60',height_cm:'165',waist_cm:'80',sbp:'120',dbp:'75',pulse:'72'};for(const [k,v] of Object.entries(values))f.elements[k].value=v;for(const name of ['smoking_state','alcohol_state'])f.querySelector(`[name="${name}"][value="no"]`).checked=true;f.querySelector('[name="exercise_frequency"]').checked=true;});
 const complete=dm=>p.evaluate(dm=>{const f=document.querySelector('form');f.dataset.glucoseOptional=String(dm);return ncdRequiredComplete(f);},dm);
 assert.equal(await complete(true),true);assert.equal(await p.locator('#ncd-dm-glucose-notice').isVisible(),true);
 await p.locator('#ncd-glucose').fill('100');assert.equal(await complete(true),false);
 await p.locator('label').filter({has:p.locator('[name="glucose_type"][value="fasting"]')}).click();assert.equal(await complete(true),true);
 for(const value of ['19','701']){await p.locator('#ncd-glucose').fill(value);assert.equal(await complete(true),false);}
 await p.locator('#ncd-glucose').fill('');assert.equal(await complete(false),false);assert.equal(await p.locator('#ncd-dm-glucose-notice').isVisible(),false);
 await p.locator('#ncd-glucose').fill('100');assert.equal(await complete(false),true);
 await complete(true);await p.locator('#ncd-glucose').fill('');await complete(true);
 if(process.env.NCD_SCREENSHOT_PATH)await p.screenshot({path:process.env.NCD_SCREENSHOT_PATH,fullPage:true});
 console.log('Mobile real form: DM skips; measured glucose requires fasting state; bounds enforced; switching non-DM restores requirement');
}finally{await browser.close();}})().catch(e=>{console.error(e);process.exit(1)});
