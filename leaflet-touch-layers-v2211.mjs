// Compact touch controls for every Leaflet field map; no map/GPS/data mutations.
const STYLE_ID='phc-touch-layers-style-v2211';
export function installTouchLayers(root=document){
 if(!root.getElementById(STYLE_ID)){
  const style=root.createElement('style');style.id=STYLE_ID;style.textContent=`
.leaflet-control-layers.phc-touch-layers{padding:0!important;max-width:calc(100vw - 90px);font-size:15px!important}
.phc-touch-layers .leaflet-control-layers-toggle{display:none!important}
.phc-touch-layers .leaflet-control-layers-list{display:none!important;margin:0!important;padding:6px 10px 10px!important;max-height:45vh;overflow-y:auto;overscroll-behavior:contain}
.phc-touch-layers.phc-layers-open .leaflet-control-layers-list{display:block!important}
.phc-touch-layers .phc-layers-button{display:block!important;width:auto!important;min-width:96px!important;min-height:44px!important;margin:0!important;padding:8px 12px!important;border:0!important;border-radius:4px!important;background:#fff!important;color:#174e43!important;font:700 15px/1.3 system-ui,sans-serif!important;touch-action:manipulation;cursor:pointer}
.phc-touch-layers .leaflet-control-layers-list label{display:block!important;margin:0!important;padding:0!important;font:inherit!important}
.phc-touch-layers .leaflet-control-layers-list label>span{display:flex!important;align-items:center!important;gap:8px!important;min-height:44px!important;white-space:nowrap}
.phc-touch-layers input.leaflet-control-layers-selector{position:static!important;display:inline-block!important;flex:0 0 20px!important;width:20px!important;height:20px!important;min-height:20px!important;margin:0!important;padding:0!important;border-radius:50%!important;accent-color:#087f70}
.phc-touch-layers .leaflet-control-layers-list label>span>span{font-size:15px!important;line-height:1.3!important}
`;root.head.append(style);
 }
 const controls=new Set();
 function bind(control){
  if(control.dataset.phcTouchLayers)return;
  control.dataset.phcTouchLayers='1';control.classList.add('phc-touch-layers');controls.add(control);
  const button=root.createElement('button');button.type='button';button.className='phc-layers-button';button.setAttribute('aria-expanded','false');button.setAttribute('aria-label','เปิดตัวเลือกแผนที่');button.textContent='แผนที่ ▾';control.prepend(button);
  const close=()=>{control.classList.remove('phc-layers-open','leaflet-control-layers-expanded');button.setAttribute('aria-expanded','false');button.setAttribute('aria-label','เปิดตัวเลือกแผนที่');button.textContent='แผนที่ ▾';};
  control.phcCloseLayers=close;close();
  button.addEventListener('click',event=>{
   event.preventDefault();event.stopPropagation();
   const open=!control.classList.contains('phc-layers-open');
   for(const other of controls)other.phcCloseLayers();
   if(open){control.classList.add('phc-layers-open');button.setAttribute('aria-expanded','true');button.setAttribute('aria-label','ปิดตัวเลือกแผนที่');button.textContent='ปิด ✕';}
  });
  control.addEventListener('change',event=>{if(event.target.matches('input.leaflet-control-layers-selector'))setTimeout(close,0);});
  control.addEventListener('keydown',event=>{if(event.key==='Escape'){close();button.focus();}});
 }
 function scan(){
  for(const control of controls)if(!control.isConnected)controls.delete(control);
  root.querySelectorAll('.leaflet-control-layers').forEach(bind);
 }
 scan();
 const observer=new MutationObserver(records=>{
  if(records.some(r=>[...r.addedNodes].some(n=>n.nodeType===1&&(n.matches?.('.leaflet-control-layers')||n.querySelector?.('.leaflet-control-layers')))))scan();
 });
 observer.observe(root.body,{childList:true,subtree:true});
 root.addEventListener('pointerdown',event=>{for(const control of controls)if(!control.contains(event.target))control.phcCloseLayers();},true);
 return {scan,disconnect:()=>observer.disconnect()};
}
if(typeof document!=='undefined'){
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>installTouchLayers(),{once:true});
 else installTouchLayers();
}
