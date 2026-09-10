const VERSION='1.8.29';

function injectStyle(){
  if(document.getElementById('system-about-note-v1829-style')) return;
  const style=document.createElement('style');
  style.id='system-about-note-v1829-style';
  style.textContent=`
    .privacy-note.system-about-note-v1829{
      margin-top:14px;
      padding:12px 14px;
      border:1px solid #cfe1da;
      border-radius:16px;
      background:#f3f9f6;
      color:#3f625a;
      line-height:1.45;
      font-size:.9rem;
      display:grid;
      gap:3px;
    }
    .system-about-note-v1829 strong{
      color:#185e52;
      font-size:.98rem;
      line-height:1.3;
    }
    .system-about-note-v1829 .system-about-sub{
      color:#57766e;
      font-size:.84rem;
    }
    @media(max-width:700px){
      .privacy-note.system-about-note-v1829{
        margin-top:10px;
        padding:10px 12px;
        border-radius:14px;
        font-size:.84rem;
        line-height:1.4;
      }
      .system-about-note-v1829 strong{font-size:.92rem}
      .system-about-note-v1829 .system-about-sub{font-size:.79rem}
    }
  `;
  document.head.appendChild(style);
}

function applyNote(){
  const note=document.querySelector('.privacy-note');
  if(!note) return;
  note.classList.add('system-about-note-v1829');
  note.innerHTML=`
    <strong>อสม. พลัส · งานชุมชนในมือคุณ</strong>
    <span>เชื่อมบ้าน · พิกัด · อสม. · งานสุขภาพ สำหรับพื้นที่ ต.พระบาท</span>
    <span class="system-about-sub">ข้อมูลแสดงตามสิทธิ์และพื้นที่รับผิดชอบ เพื่อช่วยลงพื้นที่ ติดตามงาน และตรวจสอบข้อมูลได้สะดวกขึ้น</span>
  `;
  const version=document.querySelector('.login-version');
  if(version) version.textContent=`Cloud v${VERSION}`;
}

export function initSystemAboutNote1829(){
  if(window.__PHC_SYSTEM_ABOUT_NOTE_1829__) return;
  window.__PHC_SYSTEM_ABOUT_NOTE_1829__=true;
  injectStyle();
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',applyNote,{once:true});
  else applyNote();
}
