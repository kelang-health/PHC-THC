const fs=require('fs'),path=require('path'),assert=require('node:assert/strict');
const root=path.join(__dirname,'../..'),read=n=>fs.readFileSync(path.join(root,n),'utf8');
const html=read('index.html'),app=read('app.js'),config=read('config.js');
const version=html.match(/name="phc-release" content="([^"]+)"/)[1];
assert(html.includes('Cloud v'+version));
const direct=html.match(/src="(\.\/config\.js[^\"]+)"/)[1];
const imported=app.match(/from ['"](\.\/config\.js[^'"]+)['"]/)[1];
assert.equal(direct,imported,'Direct bootstrap and app import must use the same cache URL');
assert.equal(new URL(direct,'https://example.test').searchParams.get('v'),version);
assert(config.includes('field-work-reporting-v200.mjs?v='+version));
assert(html.includes('app.js?v='+version));
const map=JSON.parse(html.match(/<script type="importmap">(.*?)<\/script>/s)[1]).imports;
assert(html.indexOf('type="importmap"')<html.indexOf('type="module"'));
for(const name of fs.readdirSync(root).filter(n=>/\.(mjs|js)$/.test(n))){
 for(const m of read(name).matchAll(/from\s*['"](\.\/config\.js[^'"]+)['"]/g)){
  assert.equal(map[m[1]]||m[1],direct,'Every config import must resolve to the same bootstrap: '+name);
 }
}
console.log('Release graph: passed '+version+' (meta, login, bootstrap, app, report module)');
