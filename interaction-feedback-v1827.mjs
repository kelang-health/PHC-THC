const VERSION='1.8.28';
const LOGIN_SUCCESS_KEY='phc.auth.login-success';
let popup=null,hideTimer=null,observer=null,lastOutcomeAt=0,lastSignature='';

function injectStyle(){
  if(document.getElementById('phc-feedback-style'))return;
  const style=document.createElement('style');
  style.id='phc-feedback-style';
  style.textContent=`
    .phc-feedback{position:fixed;z-index:10050;left:50%;bottom:calc(92px + env(safe-area-inset-bottom,0px));transform:translate(-50%,18px);width:min(430px,calc(100vw - 28px));display:grid;grid-template-columns:auto 1fr;gap:12px;align-items:center;padding:16px 18px;border:2px solid #c7ddd5;border-radius:20px;background:#fff;color:#17312d;box-shadow:0 18px 55px #102e2840;opacity:0;pointer-events:none;transition:.18s ease}
    .phc-feedback.show{opacity:1;transform:translate(-50%,0)}.phc-feedback[hidden]{display:none!important}
    .phc-feedback-icon{width:50px;height:50px;display:grid;place-items:center;border-radius:50%;background:#e6f3ef;font-size:1.6rem}
    .phc-feedback strong{display:block;font-size:1.16rem;line-height:1.3}.phc-feedback p{margin:3px 0 0;color:#5b706a;font-size:.98rem;line-height:1.4}
    .phc-feedback.success{border-color:#83c5ad}.phc-feedback.success .phc-feedback-icon{background:#daf2e6;color:#12634e}
    .phc-feedback.error{border-color:#e0a79d}.phc-feedback.error .phc-feedback-icon{background:#fee7e2;color:#9b3d31}
    .phc-feedback.loading .phc-feedback-icon{animation:phc-feedback-pulse 1s ease-in-out infinite}
    @keyframes phc-feedback-pulse{50%{transform:scale(.88);opacity:.68}}
    @media(min-width:800px){.phc-feedback{bottom:28px}}
    @media(prefers-reduced-motion:reduce){.phc-feedback{transition:none}.phc-feedback.loading .phc-feedback-icon{animation:none}}
  `;
  document.head.appendChild(style);
}

function ensurePopup(){
  if(popup&&document.body.contains(popup))return popup;
  popup=document.createElement('div');
  popup.className='phc-feedback';
  popup.hidden=true;
  popup.setAttribute('role','status');
  popup.setAttribute('aria-live','polite');
  popup.innerHTML='<span class="phc-feedback-icon" aria-hidden="true">✓</span><div><strong></strong><p></p></div>';
  document.body.appendChild(popup);
  return popup;
}

function show(kind,title,detail,duration=2200){
  const box=ensurePopup();
  clearTimeout(hideTimer);
  box.hidden=false;
  box.className=`phc-feedback ${kind}`;
  box.querySelector('.phc-feedback-icon').textContent=kind==='success'?'✓':kind==='error'?'!':kind==='loading'?'…':'●';
  box.querySelector('strong').textContent=title;
  box.querySelector('p').textContent=detail||'';
  requestAnimationFrame(()=>box.classList.add('show'));
  if(kind==='success'||kind==='error')lastOutcomeAt=Date.now();
  if(duration>0)hideTimer=setTimeout(()=>{box.classList.remove('show');setTimeout(()=>{box.hidden=true;},190);},duration);
}

function feedbackFromElement(element){
  if(!element||element.nodeType!==1)return;
  const candidates=[element,...element.querySelectorAll?.('.good,.bad,#ncd-save-confirmation')||[]];
  for(const candidate of candidates){
    if(candidate.id==='ncd-save-confirmation'&&!candidate.hidden){
      const signature='ncd-save-success';
      if(lastSignature!==signature){lastSignature=signature;show('success','บันทึกเรียบร้อยแล้ว','ระบบได้รับและจัดเก็บข้อมูลแล้ว');}
      continue;
    }
    const text=String(candidate.textContent||'').replace(/\s+/g,' ').trim();
    if(!text)continue;
    const isGood=candidate.classList?.contains('good');
    const isBad=candidate.classList?.contains('bad');
    const success=isGood&&/(บันทึก|เพิ่มบ้าน|แก้ไข).*(แล้ว|เรียบร้อย)/.test(text);
    const failure=isBad&&/(บันทึกไม่สำเร็จ|ไม่สามารถบันทึก|เกิดข้อผิดพลาด)/.test(text);
    if(!success&&!failure)continue;
    const signature=`${success?'ok':'bad'}:${text}`;
    if(signature===lastSignature)continue;
    lastSignature=signature;
    show(success?'success':'error',success?'บันทึกเรียบร้อยแล้ว':'บันทึกไม่สำเร็จ',text,success?2400:3600);
  }
}

function watchFeedback(){
  observer=new MutationObserver(mutations=>{
    for(const mutation of mutations){
      const target=mutation.target.nodeType===1?mutation.target:mutation.target.parentElement;
      feedbackFromElement(target);
    }
  });
  observer.observe(document.body,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['hidden','class']});
}

function handleSaveClick(event){
  const button=event.target.closest?.('button');
  if(!button||button.disabled)return;
  const label=String(button.textContent||'').replace(/\s+/g,' ').trim();
  if(!/บันทึก/.test(label))return;
  const clickedAt=Date.now();
  const isReview=/ตรวจสอบก่อนบันทึก|กลับไป.*บันทึก/.test(label);
  setTimeout(()=>{
    if(lastOutcomeAt>=clickedAt)return;
    const current=String(button.textContent||'').replace(/\s+/g,' ').trim();
    if(button.disabled||/กำลังบันทึก/.test(current)){
      show('loading','รับคำสั่งแล้ว','กำลังบันทึกข้อมูล กรุณารอสักครู่',12000);
    }else{
      show('info','กดแล้ว',isReview?'เปิดข้อมูลให้ตรวจสอบก่อนยืนยันบันทึกแล้ว':'ระบบรับคำสั่งแล้ว',1700);
    }
  },80);
}

function consumeLoginSuccess(){
  try{
    if(sessionStorage.getItem(LOGIN_SUCCESS_KEY)!=='1')return;
    sessionStorage.removeItem(LOGIN_SUCCESS_KEY);
    setTimeout(()=>show('success','เข้าสู่ระบบแล้ว','ยินดีต้อนรับ กำลังแสดงเมนูตามสิทธิ์ของคุณ',2600),420);
  }catch{}
}

function setVersion(){const element=document.querySelector('.login-version');if(element)element.textContent=`Cloud v${VERSION}`;}

export async function initInteractionFeedback1827(){
  if(window.__PHC_INTERACTION_FEEDBACK_1827__)return;
  window.__PHC_INTERACTION_FEEDBACK_1827__=true;
  injectStyle();ensurePopup();setVersion();consumeLoginSuccess();
  document.addEventListener('click',handleSaveClick,true);
  watchFeedback();
  window.PHCFeedback={show,success:(title,detail)=>show('success',title,detail),error:(title,detail)=>show('error',title,detail),loading:(title,detail)=>show('loading',title,detail,12000)};
}
