const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('app.js','utf8');
const helper=source.slice(source.indexOf('function cloudPasswordPolicyError('),source.indexOf("$('#change-password').addEventListener"));
const context={};vm.createContext(context);vm.runInContext(helper,context);
for(const role of ['user','staff']){
 assert.equal(context.cloudPasswordPolicyError(role,'012345'),'');
 for(const value of ['12345','1234567','abcdef','12345 ','１２３４５６'])assert.notEqual(context.cloudPasswordPolicyError(role,value),'');
}
assert.notEqual(context.cloudPasswordPolicyError('admin','123456'),'');
assert.equal(context.cloudPasswordPolicyError('admin','long-password'),'');
assert.match(source,/input\.minLength=usePin\?6:12/);
assert.match(source,/input\.maxLength=usePin\?6:128/);
console.log('PIN role, length, numeric and leading-zero checks passed');
