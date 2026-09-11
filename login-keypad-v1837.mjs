const $=(selector,root=document)=>root.querySelector(selector);
const $$=(selector,root=document)=>[...root.querySelectorAll(selector)];

function setOptionalAttribute(element,name,value){
  if(value===null) element.removeAttribute(name);
  else element.setAttribute(name,value);
}

function initLoginKeypad(){
  const form=$('#login-form');
  const card=$('#login-card');
  const login=$('#login-name');
  const password=$('#login-password');
  const loginLabel=$('#login-name-label');
  const passwordLabel=$('#login-password-label');
  const help=$('#login-keyboard-help');
  const buttons=$$('[data-login-mode]',form);
  if(!form||!card||!login||!password||!buttons.length)return;
  let mode='user';

  function applyMode(next,{focus=false}={}){
    mode=next==='staff'?'staff':'user';
    const numeric=mode==='user';
    card.dataset.loginMode=mode;
    buttons.forEach(button=>{
      const active=button.dataset.loginMode===mode;
      button.classList.toggle('active',active);
      button.setAttribute('aria-pressed',String(active));
    });
    login.type=numeric?'tel':'email';
    login.inputMode=numeric?'numeric':'email';
    login.removeAttribute('placeholder');
    password.inputMode=numeric?'numeric':'text';
    password.removeAttribute('placeholder');
    setOptionalAttribute(login,'pattern',numeric?'[0-9]*':null);
    setOptionalAttribute(login,'maxlength',numeric?'10':null);
    setOptionalAttribute(password,'pattern',numeric?'[0-9]*':null);
    setOptionalAttribute(password,'maxlength',numeric?'12':null);
    if(loginLabel)loginLabel.textContent='ชื่อผู้ใช้';
    if(passwordLabel)passwordLabel.textContent='รหัสผ่าน';
    if(help)help.textContent='หากเข้าสู่ระบบไม่ได้ กรุณาติดต่อเจ้าหน้าที่';
    if(focus)login.focus({preventScroll:true});
  }

  buttons.forEach(button=>button.addEventListener('click',()=>applyMode(button.dataset.loginMode,{focus:true})));
  login.addEventListener('input',()=>{
    if(login.value.includes('@')&&mode!=='staff')applyMode('staff');
  });
  const syncAutofill=()=>applyMode(login.value.includes('@')?'staff':mode);
  applyMode(login.value.includes('@')?'staff':'user');
  setTimeout(syncAutofill,250);
  setTimeout(syncAutofill,1000);
}

function initPasswordChangeKeypad(){
  const card=$('#password-card');
  const help=$('#password-help');
  const inputs=$$('#password-form input[type="password"]');
  if(!card||!help||!inputs.length)return;
  const apply=()=>{
    const numeric=/PIN/.test(help.textContent||'');
    inputs.forEach(input=>{
      input.inputMode=numeric?'numeric':'text';
      setOptionalAttribute(input,'pattern',numeric?'[0-9]*':null);
      setOptionalAttribute(input,'maxlength',numeric?'12':null);
    });
  };
  apply();
  new MutationObserver(apply).observe(card,{attributes:true,attributeFilter:['hidden'],subtree:true,childList:true,characterData:true});
}

initLoginKeypad();
initPasswordChangeKeypad();
