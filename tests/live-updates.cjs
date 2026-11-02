const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const html=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
const live=html.slice(html.indexOf('let requestsChannel='),html.indexOf('function priceFingerprint('));
const chat=html.slice(html.indexOf('let chatRenderTimer='),html.indexOf('let inboxLoadPromise='));
const read=html.slice(html.indexOf('async function loadChatMessages('),html.indexOf('async function openChat('));
const inbox=html.slice(html.indexOf('let inboxLoadPromise='),html.indexOf('el("chatLauncher").onclick='));
function client(){
 let queries=0,subscription,handlers=[],timers=[],renders=0;
 const listeners={},nodes=new Map();
 const context=vm.createContext({
  currentUser:{id:'user',email:'user@example.test'},WORKSPACE_ID:'team',requests:[],inboxMessages:[],currentChatRequest:null,currentChatPeer:null,
  document:{hidden:false,addEventListener(name,fn){listeners[name]=fn}},
  setTimeout(fn){timers.push(fn);return fn},clearTimeout(id){timers=timers.filter(fn=>fn!==id)},
  setInterval(){throw Error('Background polling is forbidden')},clearInterval(){},
  el(id){if(!nodes.has(id))nodes.set(id,{dataset:{},classList:{contains(){return false}},innerHTML:''});return nodes.get(id)},
  db:{from(){queries++;throw Error('Unexpected per-event database request')},removeChannel(){},channel(){return {on(type,filter,fn){handlers.push({filter,fn});return this},subscribe(fn){subscription=fn;return this}}}},
  loadRequestOwners:async()=>{},loadChatInbox:async()=>{},loadChatThreads:async()=>{},loadChatMessages:async()=>{},
  refreshPriceAlerts(){},renderRequests(){renders++},renderChatInbox(){},updateChatUnread(){},toast(){},connectionErrorMessage(e){return e.message},
  renderChatMessages(){},markChatMessagesRead(){}
 });
 vm.runInContext(live+chat,context);
 return {context,listeners,nodes,run:s=>vm.runInContext(s,context),get queries(){return queries},get renders(){return renders},
  async flush(){const queue=timers;timers=[];for(const fn of queue)await fn()},
  status(s){subscription(s)},event(table,payload){handlers.find(h=>h.filter.table===table).fn(payload)},get timers(){return timers.length}};
}
const row=(id,extra={})=>({id,workspace_id:'team',created_by:'user',created_at:'2026-11-02T07:00:00Z',loading_country:'LT',delivery_country:'DE',...extra});
(async()=>{
 const a=client(),b=client();
 for(const c of [a,b])c.run('startRequestUpdates()');
 for(const change of [row(1),row(1,{price_eur:1200}),row(1,{loading_country:'PL'}),row(2)]){
  for(const c of [a,b])c.event('transport_requests',{eventType:'UPDATE',new:change});
 }
 assert.equal(a.context.requests.length,2);
 assert.equal(b.context.requests.find(r=>r.id===1).loading_country,'PL');
 assert.equal(a.queries+b.queries,0,'Live row payloads must not cause extra reads');
 a.context.document.hidden=true;
 a.event('transport_requests',{eventType:'UPDATE',new:row(1,{price_eur:1500})});
 assert.equal(a.context.requests.find(r=>r.id===1).price_eur,1500,'Background tabs retain received changes');
 a.context.document.hidden=false;a.listeners.visibilitychange();await a.flush();
 assert.equal(a.queries,0,'Returning to an unchanged connected tab must use its cache');
 a.event('transport_requests',{eventType:'UPDATE',new:row(1,{deleted_at:'now'})});
 assert.equal(a.context.requests.length,1,'Soft deletion removes the row');
 a.event('transport_requests',{eventType:'UPDATE',new:row(1)});
 assert.equal(a.context.requests.length,2,'Restored requests reappear');
 a.event('transport_requests',{eventType:'DELETE',old:{id:1}});
 assert.equal(a.context.requests.length,1);
 a.event('transport_requests',{eventType:'UPDATE',new:row(99,{workspace_id:'other'})});
 assert.equal(a.context.requests.length,1,'Other workspaces are ignored');
 const message={id:10,workspace_id:'team',request_id:2,sender_id:'other',chat_peer_id:'user',message:'hello',created_at:'2026-11-02T07:00:00Z'};
 for(const c of [a,b]){c.event('transport_messages',{new:message});c.event('transport_messages',{new:message})}
 assert.equal(a.context.inboxMessages.length,1,'Own INSERT response and event are deduplicated');
 assert.equal(b.context.inboxMessages.length,1);
 a.run('stopRequestUpdates()');a.event('transport_requests',{eventType:'UPDATE',new:row(100)});
 assert.equal(a.context.requests.some(r=>r.id===100),false,'Stopped subscriptions must ignore late callbacks');
 // In-flight snapshots must not replace a newer event, or data from a new login.
 const c=client();let finish;
 c.context.db.from=()=>({select(){return this},eq(){return this},is(){return this},order(){return this},range(){return new Promise(resolve=>{finish=resolve})}});
 const snapshot=c.run('loadRequests()');
 c.run('refreshChangedRequest('+JSON.stringify({eventType:'UPDATE',new:row(1,{price_eur:2000})})+')');
 finish({data:[row(1,{price_eur:1000})],error:null});await snapshot;
 assert.equal(c.context.requests[0].price_eur,2000,'Newer event wins over older snapshot');
 const stale=c.run('loadRequests()');c.context.currentUser={id:'different'};
 finish({data:[row(999)],error:null});await stale;
 assert.equal(c.context.requests.some(r=>r.id===999),false,'Old account responses must be discarded');
 // Rejoins schedule exactly one reconciliation, without a periodic poll.
 const d=client();let snapshots=0;
 d.run('startRequestUpdates()');d.context.loadRequests=async()=>{snapshots++};
 d.status('SUBSCRIBED');d.status('SUBSCRIBED');await d.flush();
 assert.equal(snapshots,1);assert.equal(d.timers,0);
 d.status('CHANNEL_ERROR');d.status('SUBSCRIBED');await d.flush();
 assert.equal(snapshots,2,'Reconnect must catch missed changes');
 // Viewing messages and opening a cached inbox do not query the server.
 vm.runInContext(inbox+read,d.context);
 d.context.currentChatRequest={id:2};d.context.currentChatPeer='user';d.context.inboxMessages=[message];
 d.context.escapeHtml=String;d.context.ownerInitials=()=>'';d.context.requestOwners=[];
 await d.run('loadChatMessages()');
 d.run('inboxCacheUser=currentUser.id');await d.run('loadChatInbox()');
 assert.equal(d.queries,0);
 assert.doesNotMatch(html,/setInterval\(/,'No list or chat polling may remain');
 console.log('PASS: two clients, idle tab, hidden updates, price/route/delete/restore, chat deduplication, account isolation, snapshot race and reconnect');
})().catch(error=>{console.error(error);process.exitCode=1});

