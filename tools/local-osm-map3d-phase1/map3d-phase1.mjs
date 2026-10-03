const DEFAULT_CENTER=[99.5071,18.2696];
const DEFAULT_ZOOM=13.5;
const SOURCE_HOUSES='prb-houses';
const SOURCE_COMMUNITIES='prb-communities';
const SOURCE_BUILDINGS='prb-buildings';
const SOURCE_DEM='prb-dem';
const SOURCE_RAIN='prb-rain';

function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function isCoord(h){return Number.isFinite(Number(h?.latitude))&&Number.isFinite(Number(h?.longitude));}
function statusOf(h){
  if(!isCoord(h))return 'missing';
  if(h.review_required)return 'review';
  if(h.inside_tambon===false||h.inside_community===false)return 'boundary';
  if(['gps','map','local_verified'].includes(String(h.coordinate_source||''))||String(h.geo_quality||'')==='verified')return 'field';
  return 'legacy';
}
function healthIndexOf(data){
  const m=new Map();
  for(const x of data?.items||[])if(x?.hcode)m.set(String(x.hcode),x);
  return m;
}
function housesGeoJSON(rows,healthIndex){
  return {type:'FeatureCollection',features:(rows||[]).filter(isCoord).map(h=>{
    const health=healthIndex.get(String(h.hcode||''))||{};
    return {type:'Feature',geometry:{type:'Point',coordinates:[Number(h.longitude),Number(h.latitude)]},properties:{
      id:String(h.id||''),hcode:String(h.hcode||''),house_no:String(h.house_no||''),moo:String(h.moo||''),community:String(h.community||''),
      source:String(h.coordinate_source||''),coordinate_status:String(h.coordinate_status||''),review_required:Boolean(h.review_required),
      inside_tambon:h.inside_tambon!==false,inside_community:h.inside_community!==false,status:statusOf(h),updated_at:String(h.updated_at||''),
      health_level:String(health.level||'none'),ncd_target:Number(health.target||0),ncd_followup:Number(health.followup||0),
      ncd_risk:Number(health.risk||0),ncd_due:Number(health.due||0),ncd_known:Number(health.known_ncd||0)
    }};
  })};
}
function communitiesGeoJSON(rows){
  const features=[];
  for(const c of rows||[]){
    let g=c.geometry_geojson;
    if(typeof g==='string'){try{g=JSON.parse(g);}catch{g=null;}}
    if(!g)continue;
    features.push({type:'Feature',geometry:g,properties:{name:String(c.name||''),moo:String(c.moo||'')}});
  }
  return {type:'FeatureCollection',features};
}
async function ensureMapLibre(){
  if(window.maplibregl)return window.maplibregl;
  await new Promise((resolve,reject)=>{
    if(!document.querySelector('link[data-prb-maplibre]')){
      const l=document.createElement('link');l.rel='stylesheet';l.dataset.prbMaplibre='1';
      l.href='/assets/vendor/maplibre-gl.css';document.head.appendChild(l);
    }
    const existing=document.querySelector('script[data-prb-maplibre]');
    if(existing){existing.addEventListener('load',resolve,{once:true});existing.addEventListener('error',reject,{once:true});return;}
    const s=document.createElement('script');s.src='/assets/vendor/maplibre-gl.js';
    s.async=true;s.dataset.prbMaplibre='1';s.onload=resolve;s.onerror=reject;document.head.appendChild(s);
  });
  return window.maplibregl;
}
function rasterStyle(){
  return {version:8,sources:{
    osm:{type:'raster',tiles:['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],tileSize:256,attribution:'© OpenStreetMap contributors'},
    satellite:{type:'raster',tiles:['https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'],tileSize:256,attribution:'Tiles © Esri'}
  },layers:[
    {id:'base-background',type:'background',paint:{'background-color':'#eef5f2'}},
    {id:'osm',type:'raster',source:'osm'},
    {id:'satellite',type:'raster',source:'satellite',layout:{visibility:'none'}}
  ]};
}
export async function initPRBMap3D({container,provider,onOpenHouse,center=DEFAULT_CENTER,zoom=DEFAULT_ZOOM,initial3D=false}={}){
  if(!container)throw new Error('MAP3D_CONTAINER_REQUIRED');
  if(!provider?.getHouses||!provider?.getCommunities)throw new Error('MAP3D_PROVIDER_REQUIRED');
  const maplibregl=await ensureMapLibre();
  const map=new maplibregl.Map({container,style:rasterStyle(),center,zoom,pitch:initial3D?55:0,bearing:initial3D?-18:0,antialias:true});
  map.addControl(new maplibregl.NavigationControl({visualizePitch:true}),'top-right');
  let allHouses=[],communities=[],community='',mode3D=initial3D,layerMode='coordinate',healthIndex=new Map(),terrainOn=false,rainOn=false;
  await new Promise((resolve,reject)=>{map.once('load',resolve);map.once('error',e=>reject(e.error||e));});

  map.addSource(SOURCE_HOUSES,{type:'geojson',data:housesGeoJSON([],healthIndex),cluster:true,clusterRadius:42,clusterMaxZoom:16,
    clusterProperties:{ncd_followup_sum:['+',['get','ncd_followup']]}});
  map.addLayer({id:'house-clusters',type:'circle',source:SOURCE_HOUSES,filter:['has','point_count'],paint:{
    'circle-color':'#0f766e','circle-radius':['step',['get','point_count'],18,100,24,500,31],'circle-stroke-width':2,'circle-stroke-color':'#fff'
  }});
  map.addLayer({id:'house-cluster-count',type:'symbol',source:SOURCE_HOUSES,filter:['has','point_count'],layout:{'text-field':['get','point_count_abbreviated'],'text-size':12},paint:{'text-color':'#fff'}});
  map.addLayer({id:'house-points',type:'circle',source:SOURCE_HOUSES,filter:['!',['has','point_count']],paint:{
    'circle-radius':['interpolate',['linear'],['zoom'],12,4,17,8,20,11],
    'circle-color':['match',['get','status'],'field','#16a36f','review','#f59e0b','boundary','#ef4444','legacy','#3b82f6','#94a3b8'],
    'circle-stroke-width':2,'circle-stroke-color':'#fff'
  }});
  map.addLayer({id:'house-labels',type:'symbol',source:SOURCE_HOUSES,minzoom:17.5,filter:['!',['has','point_count']],layout:{'text-field':['get','house_no'],'text-size':11,'text-offset':[0,1.25]},paint:{'text-color':'#15342e','text-halo-color':'#fff','text-halo-width':1.5}});
  map.addSource(SOURCE_COMMUNITIES,{type:'geojson',data:communitiesGeoJSON([])});
  map.addLayer({id:'community-fill',type:'fill',source:SOURCE_COMMUNITIES,paint:{'fill-color':'#0f766e','fill-opacity':0.055}});
  map.addLayer({id:'community-line',type:'line',source:SOURCE_COMMUNITIES,paint:{'line-color':'#0f766e','line-width':2.5,'line-opacity':0.9}});
  map.addSource(SOURCE_BUILDINGS,{type:'geojson',data:{type:'FeatureCollection',features:[]}});
  map.addLayer({id:'osm-buildings-3d',type:'fill-extrusion',source:SOURCE_BUILDINGS,minzoom:14,layout:{visibility:initial3D?'visible':'none'},paint:{
    'fill-extrusion-color':'#c8d2cf','fill-extrusion-height':['get','height'],'fill-extrusion-base':0,'fill-extrusion-opacity':0.72
  }},'house-clusters');

  map.addSource(SOURCE_DEM,{type:'raster-dem',tiles:['https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'],tileSize:256,maxzoom:15,encoding:'terrarium'});
  map.addLayer({id:'terrain-hillshade',type:'hillshade',source:SOURCE_DEM,layout:{visibility:'none'},paint:{'hillshade-exaggeration':0.35}},'community-fill');

  function updateHouseSource(){map.getSource(SOURCE_HOUSES)?.setData(housesGeoJSON(allHouses,healthIndex));}
  function applyHousePaint(){
    if(layerMode==='ncd'){
      map.setPaintProperty('house-points','circle-color',['match',['get','health_level'],
        'urgent','#b91c1c','alert','#ea580c','risk','#f59e0b','due','#2563eb','normal','#16a36f','no_data','#64748b','#cbd5e1']);
      map.setPaintProperty('house-points','circle-radius',['interpolate',['linear'],['zoom'],12,5,17,9,20,12]);
      map.setPaintProperty('house-clusters','circle-color',['case',['>', ['get','ncd_followup_sum'],0],'#9a3412','#0f766e']);
    }else{
      map.setPaintProperty('house-points','circle-color',['match',['get','status'],'field','#16a36f','review','#f59e0b','boundary','#ef4444','legacy','#3b82f6','#94a3b8']);
      map.setPaintProperty('house-points','circle-radius',['interpolate',['linear'],['zoom'],12,4,17,8,20,11]);
      map.setPaintProperty('house-clusters','circle-color','#0f766e');
    }
  }
  async function refresh(nextCommunity=community){
    community=nextCommunity||'';
    const [hs,cs]=await Promise.all([provider.getHouses({community}),provider.getCommunities()]);
    allHouses=hs||[];communities=cs||[];
    updateHouseSource();
    map.getSource(SOURCE_COMMUNITIES)?.setData(communitiesGeoJSON(communities));
    return {houses:allHouses,communities};
  }
  function setBase(mode){
    const satellite=mode==='satellite';
    map.setLayoutProperty('osm','visibility',satellite?'none':'visible');
    map.setLayoutProperty('satellite','visibility',satellite?'visible':'none');
    return satellite?'satellite':'osm';
  }
  function set3D(next){
    mode3D=Boolean(next);
    map.easeTo({pitch:mode3D?55:0,bearing:mode3D?-18:0,duration:450});
    if(map.getLayer('osm-buildings-3d'))map.setLayoutProperty('osm-buildings-3d','visibility',mode3D?'visible':'none');
    return mode3D;
  }
  function setBuildings(data){
    const geo=data&&data.type==='FeatureCollection'?data:{type:'FeatureCollection',features:[]};
    map.getSource(SOURCE_BUILDINGS)?.setData(geo);
    return geo.features?.length||0;
  }
  function setHealth(data){
    healthIndex=healthIndexOf(data);
    updateHouseSource();
    applyHousePaint();
    return {houses:healthIndex.size,summary:data?.summary||{}};
  }
  function setLayerMode(mode){
    layerMode=mode==='ncd'?'ncd':'coordinate';
    applyHousePaint();
    return layerMode;
  }
  function setTerrain(next){
    terrainOn=Boolean(next);
    if(terrainOn){
      map.setTerrain({source:SOURCE_DEM,exaggeration:1.2});
      map.setLayoutProperty('terrain-hillshade','visibility','visible');
    }else{
      map.setTerrain(null);
      map.setLayoutProperty('terrain-hillshade','visibility','none');
    }
    return terrainOn;
  }
  function setRain(data){
    if(map.getLayer('rain-radar'))map.removeLayer('rain-radar');
    if(map.getSource(SOURCE_RAIN))map.removeSource(SOURCE_RAIN);
    const url=String(data?.tile_url||'');
    if(!data?.available||!url){rainOn=false;return false;}
    map.addSource(SOURCE_RAIN,{type:'raster',tiles:[url],tileSize:256,minzoom:0,maxzoom:7});
    map.addLayer({id:'rain-radar',type:'raster',source:SOURCE_RAIN,paint:{'raster-opacity':0.58,'raster-resampling':'linear'}},'house-clusters');
    rainOn=true;
    return true;
  }
  function clearRain(){
    if(map.getLayer('rain-radar'))map.removeLayer('rain-radar');
    if(map.getSource(SOURCE_RAIN))map.removeSource(SOURCE_RAIN);
    rainOn=false;
  }
  function focusHouse(id){
    const h=allHouses.find(x=>String(x.id)===String(id));if(!h||!isCoord(h))return false;
    map.flyTo({center:[Number(h.longitude),Number(h.latitude)],zoom:19,pitch:mode3D?58:0,duration:650});return true;
  }
  function search(q){
    q=String(q||'').trim().toLowerCase();if(!q)return allHouses.slice(0,50);
    return allHouses.filter(h=>[h.house_no,h.house_id_11,h.hcode,h.community].some(v=>String(v||'').toLowerCase().includes(q))).slice(0,100);
  }

  map.on('click','house-clusters',async e=>{
    const f=e.features?.[0];if(!f)return;
    const src=map.getSource(SOURCE_HOUSES);const z=await src.getClusterExpansionZoom(f.properties.cluster_id);
    map.easeTo({center:f.geometry.coordinates,zoom:z});
  });
  map.on('click','house-points',e=>{
    const f=e.features?.[0];if(!f)return;const p=f.properties||{};const coords=f.geometry.coordinates.slice();
    const health=layerMode==='ncd'&&Number(p.ncd_target||0)>0
      ? '<hr><div><strong>งาน NCD ระดับบ้าน</strong></div><div>กลุ่มเป้าหมาย '+esc(p.ncd_target)+' · ต้องติดตาม '+esc(p.ncd_followup)+'</div><div>เสี่ยง/โรคเดิม '+esc(p.ncd_risk)+' · คงค้าง '+esc(p.ncd_due)+'</div>'
      : '';
    const html='<div class="prb-map3d-popup"><strong>บ้าน '+esc(p.house_no||'ไม่ระบุ')+'</strong><div>'+esc(p.community||'')+' · หมู่ '+esc(p.moo||'—')+'</div><div>แหล่งพิกัด: '+esc(p.source||'—')+'</div><div>สถานะ: '+esc(p.coordinate_status||p.status||'—')+'</div>'+health+'<button type="button" data-map3d-open-house="'+esc(p.id)+'">เปิดข้อมูลบ้าน</button></div>';
    const popup=new maplibregl.Popup({offset:18}).setLngLat(coords).setHTML(html).addTo(map);
    setTimeout(()=>popup.getElement()?.querySelector('[data-map3d-open-house]')?.addEventListener('click',()=>onOpenHouse?.(p.id)),0);
  });
  for(const layer of ['house-points','house-clusters']){
    map.on('mouseenter',layer,()=>map.getCanvas().style.cursor='pointer');
    map.on('mouseleave',layer,()=>map.getCanvas().style.cursor='');
  }
  await refresh('');
  return {
    map,refresh,setBase,set3D,setBuildings,setHealth,setLayerMode,setTerrain,setRain,clearRain,focusHouse,search,
    getState:()=>({mode3D,community,layerMode,terrainOn,rainOn,houses:allHouses,communities})
  };
}