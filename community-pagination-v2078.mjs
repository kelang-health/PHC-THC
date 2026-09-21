// Community paging is presentation-only. Existing scoped requests remain the source of data.
const esc = value => String(value ?? '').replace(/[&<>"']/g, char => ({
  '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;',
}[char]));
const displayNum = n => Number(n).toLocaleString('th-TH');
const collator = new Intl.Collator('th', {numeric:true,sensitivity:'base'});
const clean = value => String(value ?? '').trim();
const compare = (a,b) => collator.compare(clean(a),clean(b));
const givenName = value => clean(value).replace(/^(?:นางสาว|นาง|นาย|น[.]ส[.]|ดร[.])\s*/u,'').trim();
const identity = row => clean(row?.id ?? row?.source_pid ?? row?.volunteer_pid ?? row?.hcode);
const HOUSE_ACTIONS = Object.freeze(['houses','unassigned','review']);
export const COMMUNITY_PAGE_SIZES = Object.freeze({
  houses:15,unassigned:15,review:15,volunteers:10,
});

export function sortedCommunityRows(rows,action) {
  const items=[...(Array.isArray(rows)?rows:[])];
  if (action === 'volunteers') {
    return items.sort((a,b)=>compare(givenName(a.display_name),givenName(b.display_name))||
      compare(a.source_pid??a.volunteer_pid,b.source_pid??b.volunteer_pid)||
      compare(identity(a),identity(b)));
  }
  if (!HOUSE_ACTIONS.includes(action)) return items;
  return items.sort((a,b)=>compare(a.moo,b.moo)||
    compare(a.house_no,b.house_no)||compare(a.hcode,b.hcode)||compare(identity(a),identity(b)));
}

export function pageCommunityRows(rows,{action='houses',query='',page=1,pageSize}={}) {
  const search=clean(query).toLocaleLowerCase('th');
  const matching=sortedCommunityRows(rows,action).filter(item=>{
    if(!search)return true;
    const keys=action==='volunteers'?[item.display_name,item.source_pid??item.volunteer_pid]:
      [item.house_no,item.hcode];
    return keys.some(value=>clean(value).toLocaleLowerCase('th').includes(search));
  });
  const size=Math.max(1,Math.min(100,Number(pageSize)||COMMUNITY_PAGE_SIZES[action]||15));
  const pages=Math.max(1,Math.ceil(matching.length/size));
  const current=Math.max(1,Math.min(pages,Math.trunc(Number(page)||1)));
  const start=(current-1)*size;
  return {
    rows:matching.slice(start,start+size),total:matching.length,
    page:current,pages,start,end:Math.min(start+size,matching.length),
    size,
  };
}

export function createCommunityPager({
  section,action,rows=[],renderRows,onRendered=()=>{},scrollToList=()=>{},
}) {
  const container=section.querySelector('[data-community-records]');
  if(!container)throw new Error('Community list container missing for '+action);
  const person=action==='volunteers';
  const label=person?'คน':'หลัง';
  const filter=document.createElement('div');
  filter.className='community-paged-search';
  filter.innerHTML='<label><span>'+ (person?'ค้นหาชื่อ–นามสกุล อสม.':'ค้นหาบ้านเลขที่หรือ HCODE') +
    '</span><input type="search" data-community-search autocomplete="off" placeholder="'+
    (person?'พิมพ์ชื่อ อสม.':'บ้านเลขที่ หรือ HCODE')+
    '" aria-label="'+(person?'ค้นหารายชื่อ อสม.':'ค้นหาบ้านเลขที่หรือ HCODE')+'"></label>'+
    '<small data-community-total aria-live="polite"></small>';
  container.before(filter);
  const pager=document.createElement('nav');
  pager.className='community-pager';
  pager.setAttribute('aria-label',person?'แบ่งหน้ารายชื่อ อสม.':'แบ่งหน้ารายการบ้าน');
  pager.innerHTML='<button type="button" class="secondary" data-page-direction="-1">← ก่อนหน้า</button>'+
    '<span data-page-status aria-live="polite"></span>'+
    '<button type="button" class="secondary" data-page-direction="1">ถัดไป →</button>';
  container.after(pager);
  const state={rows:Array.isArray(rows)?rows:[],page:1,query:'',hasRendered:false};
  const input=filter.querySelector('[data-community-search]');
  const draw=()=>{
    if(section.hidden){state.hasRendered=false;return;}
    const result=pageCommunityRows(state.rows,{action,query:state.query,page:state.page});
    state.page=result.page;
    container.innerHTML=renderRows(result.rows,result.start);
    filter.querySelector('[data-community-total]').textContent=
      state.query?'พบ '+displayNum(result.total)+' '+label+' จากทั้งหมด '+displayNum(state.rows.length)+' '+label:
      'ทั้งหมด '+displayNum(state.rows.length)+' '+label;
    pager.querySelector('[data-page-status]').textContent=
      'แสดง '+displayNum(result.total?result.start+1:0)+'–'+displayNum(result.end)+
      ' จาก '+displayNum(result.total)+' '+label+' · หน้า '+displayNum(result.page)+'/'+displayNum(result.pages);
    pager.querySelector('[data-page-direction="-1"]').disabled=result.page<=1;
    pager.querySelector('[data-page-direction="1"]').disabled=result.page>=result.pages;
    state.hasRendered=true;
    onRendered();
    return result;
  };
  input.addEventListener('input',()=>{
    state.query=input.value;
    state.page=1;
    draw();
  });
  pager.querySelectorAll('[data-page-direction]').forEach(button=>button.addEventListener('click',()=>{
    const result=pageCommunityRows(state.rows,{action,query:state.query,page:state.page});
    const next=result.page+Number(button.dataset.pageDirection);
    if(next<1||next>result.pages)return;
    state.page=next;
    draw();
    scrollToList(section);
  }));
  return {
    activate(){if(!state.hasRendered)draw();},
    setRows(nextRows){
      state.rows=Array.isArray(nextRows)?nextRows:[];
      state.hasRendered=false;
      if(!section.hidden)draw();
    },
    getSnapshot(){return {action,page:state.page,query:state.query,rendered:state.hasRendered};},
    getVisibleRows(){return pageCommunityRows(state.rows,{action,query:state.query,page:state.page}).rows;},
  };
}
