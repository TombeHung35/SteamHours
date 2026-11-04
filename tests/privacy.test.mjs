import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {runInNewContext} from 'node:vm';
const read=p=>readFileSync(new URL('../harmony/entry/src/main/ets/'+p,import.meta.url),'utf8').replace(/^import[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
const model=read('model/PrivacyPolicy.ets')+'\n'+read('model/PrivacyAccess.ets');
const ctx={filesDir:'/app/files',cacheDir:'/app/cache'};
function storage(config={}){
 const maps=new Map([['steam_hours',new Map([['account','76561198000000000'],['themeColor','#123456'],['backgroundPath','/app/files/appearance/background-1-a.jpg']])],['steam_hours_library_v1',new Map([['snapshot_76561198000000000','history-one'],['snapshot_76561198000000001','history-two'],['identity_me','76561198000000000'],['sort',3]])],['steam_hours_privacy_v1',new Map(Object.entries(config.privacy??{}))]]);
 const tree=new Map([['/app/files/appearance','dir'],['/app/files/appearance/background-1-a.jpg','file'],['/app/cache','dir'],['/app/cache/nested','dir'],['/app/cache/nested/cover.jpg','file'],['/app/cache/shortcut','link'],['/photos/original.jpg','file']]);
 const removed=[],events=[];const keys=new Set(['steam_hours_personal_api_key_v1','steam_hours_family_token_v1']);let failKey=config.failKey??0;
 const preferences={getPreferences:async(_,options)=>{const m=maps.get(options.name)??new Map();maps.set(options.name,m);return {get:async(k,d)=>m.has(k)?m.get(k):d,put:async(k,v)=>m.set(k,v),clear:async()=>m.clear(),flush:async()=>{if(config.flushFailure?.(options.name,m))throw Error('disk');}};}};
 const fs={accessSync:p=>tree.has(p),lstatSync:p=>({isSymbolicLink:()=>tree.get(p)==='link',isDirectory:()=>tree.get(p)==='dir'}),listFileSync:p=>[...tree.keys()].filter(x=>x.startsWith(p+'/')&&!x.slice(p.length+1).includes('/')).map(x=>x.slice(p.length+1)),unlink:async p=>{removed.push(p);if(!tree.has(p))throw Error('missing');tree.delete(p);},rmdir:async p=>{assert.equal([...tree.keys()].some(x=>x.startsWith(p+'/')),false);removed.push(p);tree.delete(p);}};
 const api=runInNewContext(stripTypeScriptTypes(model+'\n'+read('service/PrivacyStore.ets')+'\n'+read('service/LocalDataCleaner.ets'))+'\n({PrivacyStore,LocalDataCleaner,privacyAccess,POLICY_REVISION})',{preferences,fs,deviceInfo:{sdkApiVersion:26},webview:{WebCookieManager:{clearAllCookiesSync:()=>events.push('cookies')},WebStorage:{deleteAllData:()=>events.push('webstorage')},WebviewController:{removeAllCache:()=>events.push('webcache')}},KeyStore:class {constructor(alias){this.alias=alias;}async clear(){events.push(['key',this.alias]);if(failKey-->0)throw Error('asset');keys.delete(this.alias);}}});
 return {...api,maps,tree,removed,events,fs,keys,key:()=>keys.size>0};
}

test('Consent defaults closed, restores explicit decisions and invalidates old policy versions',async()=>{
 const h=storage(),store=new h.PrivacyStore();assert.equal(await store.read(ctx),'pending');
 await store.choose(ctx,true);assert.equal(await new h.PrivacyStore().read(ctx),'granted');
 await store.choose(ctx,false);assert.equal(await store.read(ctx),'declined');
 h.maps.get('steam_hours_privacy_v1').set('revision','old-policy');assert.equal(await store.read(ctx),'pending');
 h.maps.get('steam_hours_privacy_v1').set('cleanupPending',true);assert.equal(await store.read(ctx),'blocked');
});

test('Failed consent persistence rolls in-memory values back and never grants runtime access',async()=>{
 let fail=true;const h=storage({flushFailure:()=>{if(fail){fail=false;return true;}return false;}});const store=new h.PrivacyStore();
 await assert.rejects(store.choose(ctx,true),/未能保存/);assert.equal(h.maps.get('steam_hours_privacy_v1').get('allowed'),false);assert.equal(await store.read(ctx),'pending');assert.throws(()=>h.privacyAccess.begin());
});

test('Revocation cancels once, invalidates old completions across re-consent and unregisters finished calls',()=>{
 const h=storage();assert.throws(()=>h.privacyAccess.begin());h.privacyAccess.setAllowed(true);const old=h.privacyAccess.begin();let aborted=0;
 const release=h.privacyAccess.register(()=>aborted++,old);h.privacyAccess.setAllowed(false);assert.equal(aborted,1);release();h.privacyAccess.setAllowed(true);assert.equal(aborted,1);assert.equal(h.privacyAccess.current(old),false);assert.throws(()=>h.privacyAccess.check(old));
 const current=h.privacyAccess.begin();const completed=h.privacyAccess.register(()=>aborted++,current);completed();h.privacyAccess.setAllowed(false);assert.equal(aborted,1);
});

test('Complete cleanup deletes all player snapshots, credentials, choices and owned cache while preserving original photos',async()=>{
 const h=storage();h.privacyAccess.setAllowed(true);await new h.LocalDataCleaner().clear(ctx);
 assert.equal(h.key(),false);for(const m of h.maps.values())assert.equal(m.size,0);
 assert.equal(h.tree.has('/photos/original.jpg'),true);assert.equal(h.tree.has('/app/cache/shortcut'),false);
 assert.ok(h.removed.every(p=>p.startsWith('/app/cache/')||p.startsWith('/app/files/appearance/')));
 assert.equal(await new h.PrivacyStore().read(ctx),'pending');assert.throws(()=>h.privacyAccess.begin());
});

test('Partial credential failure retains cleanup marker, continues other deletions and succeeds on retry',async()=>{
 const h=storage({failKey:1});await assert.rejects(new h.LocalDataCleaner().clear(ctx),/部分本地数据/);
 assert.equal(h.key(),true);assert.equal(h.maps.get('steam_hours').size,0);assert.equal(h.maps.get('steam_hours_library_v1').size,0);
 assert.equal(await new h.PrivacyStore().read(ctx),'blocked');assert.equal(h.tree.has('/photos/original.jpg'),true);
 await new h.LocalDataCleaner().clear(ctx);assert.equal(h.key(),false);assert.equal(await new h.PrivacyStore().read(ctx),'pending');
});

test('A failed cleanup marker stops deletion, while a failed completion flush leaves retry state',async()=>{
 let fail=true;const h=storage({flushFailure:()=>{if(fail){fail=false;return true;}return false;}});
 await assert.rejects(new h.LocalDataCleaner().clear(ctx),/尚未开始删除/);assert.equal(h.events.length,0);assert.equal(h.removed.length,0);
 let once=true;const end=storage({flushFailure:(name,m)=>{if(once&&name==='steam_hours_privacy_v1'&&m.size===0){once=false;return true;}return false;}});
 await assert.rejects(new end.LocalDataCleaner().clear(ctx),/完成状态/);assert.equal(await new end.PrivacyStore().read(ctx),'blocked');
 await new end.LocalDataCleaner().clear(ctx);assert.equal(await new end.PrivacyStore().read(ctx),'pending');
});

test('Unsafe listed paths and symbolic root directories never traverse outside app storage',async()=>{
 const h=storage();h.fs.listFileSync=()=>['../../photos/original.jpg'];await assert.rejects(new h.LocalDataCleaner().clear(ctx));assert.equal(h.removed.length,0);assert.equal(h.tree.has('/photos/original.jpg'),true);
 const linked=storage();linked.tree.set('/app/files/appearance','link');await assert.rejects(new linked.LocalDataCleaner().clear(ctx));assert.equal(linked.tree.has('/photos/original.jpg'),true);assert.equal(await new linked.PrivacyStore().read(ctx),'blocked');
});

function network(kind,responder){const calls=[];let created=0,destroyed=0;const http={RequestMethod:{GET:'GET'},HttpDataType:{STRING:'STRING'},createHttp:()=>{created++;return {request:async(url,options)=>{calls.push({url:new URL(url),options});return responder(new URL(url));},destroy:()=>destroyed++};}};
 const text=model+'\n'+read('model/Library.ets')+'\n'+read('model/SteamData.ets')+'\n'+read('model/FamilyData.ets')+'\n'+read('model/AchievementData.ets')+'\n'+read('service/'+kind+'.ets');
 const api=runInNewContext(stripTypeScriptTypes(text)+'\n({privacyAccess,Client:'+kind+'})',{http});return {...api,client:new api.Client(),calls,created:()=>created,destroyed:()=>destroyed};}
const id='76561198000000000',key='a'.repeat(32);

test('Both real API clients reject without consent before allocating any HTTP request',async()=>{
 for(const kind of ['LibraryApi','AchievementsApi']){const h=network(kind,()=>{throw Error('network must stay closed');});await assert.rejects(kind==='LibraryApi'?h.client.load(id,key):h.client.load(id,400,key),/隐私/);assert.equal(h.created(),0);assert.equal(h.calls.length,0);}
});

test('Revoking a pending library request destroys it once and prevents stale result/cache repopulation',async()=>{
 let finish;const h=network('LibraryApi',()=>new Promise(resolve=>finish=resolve));h.privacyAccess.setAllowed(true);const query=h.client.load(id,key);const rejected=assert.rejects(query);await new Promise(resolve=>setImmediate(resolve));assert.equal(h.calls.length,1);
 h.privacyAccess.setAllowed(false);h.privacyAccess.setAllowed(true);finish({responseCode:200,result:JSON.stringify({response:{players:[{steamid:id,personaname:'test'}]}})});await rejected;
 assert.equal(h.destroyed(),1);assert.equal(h.client.cachedData,null);assert.equal(h.calls.length,1);
});

test('Revoking parallel achievement requests closes both and cannot populate result cache',async()=>{
 const finishes=[];const h=network('AchievementsApi',()=>new Promise(resolve=>finishes.push(resolve)));h.privacyAccess.setAllowed(true);const rejected=assert.rejects(h.client.load(id,400,key));await new Promise(resolve=>setImmediate(resolve));assert.equal(h.calls.length,2);
 h.privacyAccess.setAllowed(false);for(const finish of finishes)finish({responseCode:200,result:JSON.stringify({playerstats:{steamID:id,success:true,achievements:[]},game:{}})});await rejected;assert.equal(h.destroyed(),2);assert.equal(h.client.cachedData,null);
});

test('Startup resumes interrupted cleanup before appearance/content restore and keeps networking closed on failure',async()=>{
 const entry=read('entryability/EntryAbility.ets').replace('default class EntryAbility','class EntryAbility');
 for(const fail of [false,true]){const events=[];const api=runInNewContext(stripTypeScriptTypes(entry)+'\n({EntryAbility})',{
 UIAbility:class{},PrivacyStore:class{async read(){return 'blocked';}},LocalDataCleaner:class{async clear(){events.push('cleanup');if(fail)throw Error('disk');}},privacyAccess:{setAllowed:value=>events.push(['network',value])},
 AppearanceStore:class{async read(){events.push('appearance');return 'night';}},PersonalizationStore:class{async read(){return {themeColor:'',backgroundPath:'',backgroundOpacity:0.22,panelTransparency:0.25,foregroundBlurStrength:0.4};}},AppStorage:{setOrCreate:(key,value)=>events.push([key,value])},applyAppearance:()=>{},applyColorMode:()=>events.push('system-color-mode'),console});
 const ability=new api.EntryAbility();ability.context={};await ability.loadMainPage({loadContent:()=>events.push('render')});assert.ok(events.indexOf('cleanup')<events.indexOf('appearance'));assert.ok(events.indexOf('system-color-mode')>events.indexOf('appearance'));assert.ok(events.indexOf('system-color-mode')<events.indexOf('render'));assert.ok(events.every(e=>!Array.isArray(e)||e[0]!=='network'||e[1]===false));assert.equal(events.find(e=>Array.isArray(e)&&e[0]==='privacyStatus')[1],fail?'blocked':'pending');}
});
