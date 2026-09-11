const VERSION='1.8.51';

function injectStyle(){
  if(document.getElementById('system-about-note-v1829-style')) return;
  const style=document.createElement('style');
  style.id='system-about-note-v1829-style';
  style.textContent=`
    .privacy-note.system-about-note-v1829{
      margin:12px 0 4px;
      padding:12px 8px 10px;
      border:0;
      border-top:1px solid #d6e2dd;
      border-radius:0;
      background:transparent;
      color:#66736f;
      text-align:center;
      font-size:.86rem;
      line-height:1.5;
      font-weight:500;
    }
    @media(max-width:700px){
      .privacy-note.system-about-note-v1829{
        margin:8px 0 2px;
        padding:10px 6px 8px;
        font-size:.79rem;
        line-height:1.45;
      }
    }
  `;
  document.head.appendChild(style);
}

function applyNote(){
  const note=document.querySelector('.privacy-note');
  if(!note) return;
  note.classList.add('system-about-note-v1829');
  note.textContent=`© 2026 อสม. พลัส (VHV Plus) | Design & Developed by Apiwat Meethong | v${VERSION}`;
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
