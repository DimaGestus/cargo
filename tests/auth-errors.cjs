const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync(require('node:path').join(__dirname, '../index.html'), 'utf8');
const helper = html.slice(html.indexOf('function connectionErrorMessage('), html.indexOf('\n}', html.indexOf('function connectionErrorMessage(')) + 2);
const initialize = html.slice(html.indexOf('async function initializeApp('), html.indexOf('\ndocument.querySelectorAll("[data-close]")'));

async function checkMembership(error, membership) {
  let signOuts = 0;
  let message = '';
  const node = {classList: {remove() {}, add() {}}};
  const query = {select() {return this}, eq() {return this}, async maybeSingle() {return {data: membership, error}}};
  const context = vm.createContext({
    currentUser: null, requestViewReady: false, WORKSPACE_ID: 'workspace',
    db: {from() {return query}, auth: {async signOut() {signOuts++}}},
    el() {return node}, showMessage(id, text) {message = text}
  });
  await vm.runInContext(helper + '\n' + initialize + '\ninitializeApp({id:"member"})', context);
  return {signOuts, message};
}

(async () => {
  const restricted = await checkMembership({status: 402, message: 'Service restricted: exceed_egress_quota'}, null);
  assert.equal(restricted.signOuts, 0, 'A service restriction must preserve the session');
  assert.match(restricted.message, /Supabase.*usage and billing/);
  assert.doesNotMatch(restricted.message, /not on the RouteDesk team/);
  const temporary = await checkMembership({message: 'Failed to fetch'}, null);
  assert.equal(temporary.signOuts, 0, 'A network failure must preserve the session');
  assert.equal(temporary.message, 'Failed to fetch');
  const missing = await checkMembership(null, null);
  assert.equal(missing.signOuts, 1, 'A confirmed missing membership must still deny access');
  assert.match(missing.message, /not on the RouteDesk team/);
  const context = vm.createContext({});
  vm.runInContext(helper, context);
  assert.match(vm.runInContext('connectionErrorMessage({status:402,message:"Payment Required"})', context), /Supabase/);
  assert.equal(vm.runInContext('connectionErrorMessage({status:400,message:"Invalid login credentials"})', context), 'Invalid login credentials');
  assert.match(vm.runInContext('connectionErrorMessage("exceed_egress_quota")', context), /Supabase/);
  console.log('PASS: membership service/network failures, missing membership, 402 and normal auth messages');
})().catch(error => {console.error(error); process.exitCode = 1});

