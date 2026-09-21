const assert=require('node:assert/strict');
const puppeteer=require(process.env.PHC_PUPPETEER_PATH||'puppeteer');
const base=process.env.PHC_TEST_BASE||'http://127.0.0.1:8766/';
(async()=>{
 const browser=await puppeteer.launch({
   executablePath:process.env.PHC_CHROME_PATH||'C:/Program Files/Google/Chrome/Application/chrome.exe',
   headless:true,args:['--no-sandbox','--disable-gpu']
 });
 try{
  const page=await browser.newPage();
  await page.setViewport({width:390,height:844,deviceScaleFactor:3,isMobile:true,hasTouch:true});
  await page.goto(base,{waitUntil:'domcontentloaded',timeout:25000});
  const data=await page.evaluate(async()=>{
   const {pageCommunityRows,sortedCommunityRows,createCommunityPager}=await import('./community-pagination-v2078.mjs?v=2.0.78&p=2078');
   const {houseCards,volunteerCards,selectCommunityView}=await import('./community-workspace-v2074.mjs?v=2.0.78&p=2078');
   const houses=Array.from({length:126},(_,i)=>({
     id:'id-'+i,hcode:String(1000+i),house_no:i===2?'2/10':i===3?'2/2':String(i+1),
     moo:i%5===0?'3':'2',community:'TEST',volunteer_pid:i%5===0?null:1+i%24,
     review_required:i%4===0,member_count:2,health_access:true,
   }));
   const volunteers=Array.from({length:24},(_,i)=>({
     source_pid:i+1,display_name:i===0?'สมใจ ทดสอบ':i===1?'กนก ทดสอบ':'Volunteer '+(i+1),
     house_count:5,community:'TEST',
   }));
   const p=pageCommunityRows(houses,{action:'houses',page:6});
   if(p.total!==126||p.rows.length!==15||p.start!==75||p.pages!==9)throw Error('house page logic failed');
   const n=sortedCommunityRows([{house_no:'2/10',moo:'2',hcode:'3'}, {house_no:'2/2',moo:'2',hcode:'2'}, {house_no:'10',moo:'2',hcode:'4'},{house_no:'2',moo:'2',hcode:'1'}],'houses').map(x=>x.house_no);
   if(JSON.stringify(n)!==JSON.stringify(['2','2/2','2/10','10']))throw Error('house numeric sort failed: '+JSON.stringify(n));
   const thai=sortedCommunityRows([{display_name:'สมใจ',source_pid:2},{display_name:'กนก',source_pid:1}],'volunteers');
   if(thai[0].display_name!=='กนก')throw Error('Thai name sort failed');
   const hcode=pageCommunityRows(houses,{action:'houses',query:'1003'});
   if(hcode.total!==1||hcode.rows[0].hcode!=='1003')throw Error('HCODE search failed');
   const workspace=document.querySelector('#community-workspace');
   workspace.hidden=false;
   workspace.innerHTML='<div class="community-actions"><button data-community-action="houses">บ้าน</button><button data-community-action="volunteers">อสม.</button><button data-community-action="unassigned">ไม่มี อสม.</button><button data-community-action="review">ตรวจ</button></div>'+
     ['houses','volunteers','unassigned','review'].map(a=>'<section class="community-view" data-community-view="'+a+'" hidden><div data-community-records></div></section>').join('');
   const list={};
   let opened='';
   workspace.addEventListener('click',event=>{
     const button=event.target.closest('[data-community-house-open]');if(button)opened=button.dataset.communityHouseOpen;
   });
   for (const action of ['houses','volunteers','unassigned','review']){
     const section=workspace.querySelector('[data-community-view="'+action+'"]');
     list[action]=createCommunityPager({
       section,action,
       rows:action==='volunteers'?volunteers:action==='unassigned'?houses.filter(h=>h.volunteer_pid==null):action==='review'?houses.filter(h=>h.review_required):houses,
       renderRows:(rows,start)=>action==='volunteers'?volunteerCards(rows,houses):houseCards(rows,{indexOffset:start}),
       scrollToList:()=>{},
     });
   }
   selectCommunityView(workspace,'houses',{scroll:false});list.houses.activate();
   const initiallyRendered=workspace.querySelectorAll('[data-community-view="houses"] .community-record-card').length;
   const hiddenRendered=workspace.querySelectorAll('[data-community-view="volunteers"] .community-record-card').length;
   workspace.querySelector('[data-community-view="houses"] [data-page-direction="1"]').click();
   const second=workspace.querySelector('[data-community-view="houses"] [data-page-status]').textContent;
   const firstIndex=workspace.querySelector('[data-community-view="houses"] .community-record-index').textContent;
   const houseButton=workspace.querySelector('[data-community-view="houses"] [data-community-house-open]');
   houseButton.click();
   const beforeSwitch=list.houses.getSnapshot();
   selectCommunityView(workspace,'volunteers',{scroll:false});list.volunteers.activate();
   const volCount=workspace.querySelectorAll('[data-community-view="volunteers"] [data-community-volunteer]').length;
   workspace.querySelector('[data-community-view="volunteers"] [data-page-direction="1"]').click();
   const volPage=list.volunteers.getSnapshot().page;
   const searchInput=workspace.querySelector('[data-community-view="volunteers"] [data-community-search]');
   searchInput.value='กนก';searchInput.dispatchEvent(new Event('input',{bubbles:true}));
   const volFiltered=workspace.querySelectorAll('[data-community-view="volunteers"] [data-community-volunteer]').length;
   const volMatches=workspace.querySelector('[data-community-view="volunteers"] [data-community-records]').textContent.includes('กนก');
   selectCommunityView(workspace,'houses',{scroll:false});list.houses.activate();
   const restored=list.houses.getSnapshot();
   const visibleBefore=workspace.querySelectorAll('[data-community-view="houses"] .community-record-card').length;
   const updated=houses.map(h=>({...h,member_count:7}));
   list.houses.setRows(updated);
   const visibleAfter=workspace.querySelectorAll('[data-community-view="houses"] .community-record-card').length;
   const visiblePopulation=workspace.querySelector('[data-community-view="houses"] [data-community-records]').textContent.includes('7 คน');
   const inactiveNodes=workspace.querySelectorAll('[data-community-view="volunteers"] [data-community-volunteer]').length;
   selectCommunityView(workspace,'unassigned',{scroll:false});list.unassigned.activate();
   const unassignedCount=workspace.querySelectorAll('[data-community-view="unassigned"] .community-record-card').length;
   selectCommunityView(workspace,'review',{scroll:false});list.review.activate();
   const reviewCount=workspace.querySelectorAll('[data-community-view="review"] .community-record-card').length;
   return {initiallyRendered,hiddenRendered,second,firstIndex,opened,beforeSwitch,volCount,volPage,
     volFiltered,volMatches,restored,visibleBefore,visibleAfter,visiblePopulation,inactiveNodes,
     unassignedCount,reviewCount,houseCount:houses.length,volunteerCount:volunteers.length};
  });
  assert.equal(data.initiallyRendered,15);
  assert.equal(data.hiddenRendered,0);
  assert.ok(data.second.includes('16')&&data.second.includes('30'));
  assert.equal(data.firstIndex,'16');
  assert.ok(data.opened.startsWith('id-'));
  assert.equal(data.beforeSwitch.page,2);
  assert.equal(data.volCount,10);
  assert.equal(data.volPage,2);
  assert.equal(data.volFiltered,1);
  assert.equal(data.volMatches,true);
  assert.equal(data.restored.page,2);
  assert.equal(data.visibleBefore,15);
  assert.equal(data.visibleAfter,15);
  assert.equal(data.visiblePopulation,true);
  assert.equal(data.inactiveNodes,1);
  assert.equal(data.unassignedCount,15);
  assert.equal(data.reviewCount,15);
  const ui=await page.evaluate(()=>{
    const bar=document.querySelector('[data-community-view="review"] .community-pager');
    return {width:document.documentElement.scrollWidth,viewport:innerWidth,
      controls:bar?.querySelectorAll('button').length||0};
  });
  assert.ok(ui.width<=ui.viewport+2);
  assert.equal(ui.controls,2);
  await page.evaluate(()=>{
    const workspace=document.querySelector('#community-workspace');
    document.body.appendChild(workspace);
    workspace.hidden=false;
    document.querySelector('[data-community-view="houses"]').hidden=true;
    document.querySelector('[data-community-view="review"]').hidden=false;
  });
  const widths=[];
  for(const width of [320,375,390,430]){
    await page.setViewport({width,height:844,deviceScaleFactor:3,isMobile:width<=430,hasTouch:width<=430});
    const sample=await page.evaluate(()=>{
      const nav=document.querySelector('[data-community-view="review"] .community-pager');
      const rect=nav.getBoundingClientRect();
      const buttons=[...nav.querySelectorAll('button')].map(b=>b.getBoundingClientRect());
      return {bodyOverflow:document.documentElement.scrollWidth>innerWidth+2,
        pagerOverflow:rect.right>innerWidth+2,
        buttonOverlap:buttons[0].right>buttons[1].left-1,navRect:{left:rect.left,right:rect.right,width:rect.width},buttons:buttons.map(b=>({left:b.left,right:b.right,width:b.width}))};
    });
    assert.equal(sample.bodyOverflow,false,'page horizontal overflow at '+width);
    assert.equal(sample.pagerOverflow,false,'pager outside viewport at '+width);
    assert.equal(sample.buttonOverlap,false,'pager buttons overlap at '+width);
    widths.push({width,...sample});
  }
  const bench=await page.evaluate(async()=>{
    const {houseCards}=await import('./community-workspace-v2074.mjs?v=2.0.78&p=2078');
    const {pageCommunityRows}=await import('./community-pagination-v2078.mjs?v=2.0.78&p=2078');
    const records=Array.from({length:1000},(_,i)=>({id:'benchmark-'+i,house_no:String(i+1),hcode:String(2000+i),moo:'2',community:'TEST'}));
    const full=document.createElement('div'),paged=document.createElement('div');
    const t1=performance.now();full.innerHTML=houseCards(records);const fullMs=performance.now()-t1;
    const t2=performance.now();paged.innerHTML=houseCards(pageCommunityRows(records,{action:'houses'}).rows);const pagedMs=performance.now()-t2;
    return {allCards:full.querySelectorAll('.community-record-card').length,
      shownCards:paged.querySelectorAll('.community-record-card').length,
      allMs:Math.round(fullMs*100)/100,pagedMs:Math.round(pagedMs*100)/100};
  });
  assert.equal(bench.allCards,1000);
  assert.equal(bench.shownCards,15);
  console.log(JSON.stringify({result:'PASS',data,ui,widths,bench}));
 } finally{await browser.close();}
})().catch(e=>{console.error(e.stack||e);process.exitCode=1});
