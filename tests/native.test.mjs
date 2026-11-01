import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const privacyAccess={begin:()=>0,current:()=>true,check(){},register(){return ()=>{};}};
const ets = '../harmony/entry/src/main/ets/';
function load(file, returned, globals = {}) {
  const text = readFileSync(new URL(ets + file, import.meta.url), 'utf8')
    .replace(/^import[\s\S]*?;\r?\n/gm, '').replace(/\bexport /g, '');
  return runInNewContext(stripTypeScriptTypes(text) + '\n' + returned, globals);
}
const data = load('model/SteamData.ets', '({ parseAccount, validateApiKey, normalizeLibrary })');
const family = load('model/FamilyData.ets', '({ mergeFamilyLibrary, extractFamilyToken, isSteamLoginUrl })');
const id = '76561198000000000';
const key = 'a'.repeat(32);
const player = { steamid: id, personaname: 'Tester' };

function clientFor(responder) {
  const calls = [];
  let destroyed = 0;
  const http = {
    RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 'STRING' },
    createHttp: () => ({
      async request(url, options) {
        const parsed = new URL(url);
        calls.push({ url: parsed, options });
        return responder(parsed, options);
      },
      destroy() { destroyed += 1; }
    })
  };
  const Client = load('service/LibraryApi.ets', 'LibraryApi', { ...data, ...family, http, privacyAccess });
  return { client: new Client(), calls, destroyed: () => destroyed };
}
const json = response => ({ responseCode: 200, result: JSON.stringify({ response }) });
function normal(url) {
  if (url.pathname.includes('ResolveVanityURL')) return json({ success: 1, steamid: id });
  if (url.pathname.includes('GetPlayerSummaries')) return json({ players: [player] });
  if (url.pathname.includes('GetOwnedGames')) return json({ game_count: 2, games: [
    { appid: 730, name: 'CS2', playtime_forever: 600 }, { appid: 400, name: 'Portal', playtime_forever: 0 }
  ] });
  return json({ total_count: 1, games: [{ appid: 730, playtime_2weeks: 90 }] });
}

test('Input preserves exact SteamID and accepts only Steam profile links', () => {
  assert.equal(data.parseAccount(id).steamId, id);
  assert.equal(data.parseAccount('https://steamcommunity.com/profiles/' + id + '/?l=schinese').steamId, id);
  assert.equal(data.parseAccount('steamcommunity.com/id/player_one/').vanity, 'player_one');
  for (const input of ['', '12345', 'https://evil.example/id/name', 'https://steamcommunity.com@evil.example/id/name', 'https://steamcommunity.com/app/730']) assert.throws(() => data.parseAccount(input));
});
test('Key format rejects accidental passwords or incomplete input', () => {
  assert.equal(data.validateApiKey(' ' + key + ' '), key);
  for (const input of ['', 'password', 'z'.repeat(32), 'a'.repeat(31)]) assert.throws(() => data.validateApiKey(input));
});
test('Unavailable library is not shown as an empty library with zero hours', () => {
  const result = data.normalizeLibrary(player, {}, {}, 'now');
  assert.equal(result.gameCount, null);
  assert.equal(result.totalMinutes, null);
  assert.equal(result.recentMinutes, null);
  assert.equal(result.libraryStatus, 'unavailable');
});
test('Explicit empty responses have real zero totals', () => {
  const result = data.normalizeLibrary(player, { game_count: 0 }, { total_count: 0 }, 'now');
  assert.equal(result.gameCount, 0);
  assert.equal(result.totalMinutes, 0);
  assert.equal(result.recentMinutes, 0);
});
test('Recent and lifetime totals remain separate and unknown minutes remain null', () => {
  const result = data.normalizeLibrary(player, { games: [{ appid: 1, playtime_forever: 120 }, { appid: 2 }] }, { games: [{ appid: 1, playtime_2weeks: 30 }] }, 'now');
  assert.equal(result.totalMinutes, null);
  assert.equal(result.recentMinutes, 30);
  assert.equal(result.games[0].totalMinutes, 120);
  assert.equal(result.games[1].totalMinutes, null);
  assert.equal(result.games[1].recentMinutes, 0);
});
test('Direct requests use only official HTTPS endpoints and clean up every request', async () => {
  const fixture = clientFor(normal);
  const result = await fixture.client.load(id, key);
  assert.equal(result.player.steamId, id);
  assert.equal(result.totalMinutes, 600);
  assert.equal(result.recentMinutes, 90);
  assert.equal(fixture.calls.length, 3);
  for (const call of fixture.calls) {
    assert.equal(call.url.origin, 'https://api.steampowered.com');
    assert.equal(call.url.searchParams.has('key'), false); assert.equal(call.options.header['x-webapi-key'], key);
    assert.equal(call.options.usingCache, false);
  }
  assert.equal(fixture.destroyed(), 3);
});
test('Vanity is resolved by Steam rather than fetching the user-provided URL', async () => {
  const fixture = clientFor(normal);
  await fixture.client.load('https://steamcommunity.com/id/player_one/', key);
  assert.equal(fixture.calls.length, 4);
  assert.equal(fixture.calls[0].url.searchParams.get('vanityurl'), 'player_one');
  assert.equal(fixture.calls[1].url.searchParams.get('steamids'), id);
});
test('Cache is scoped to account and key, and can be explicitly erased', async () => {
  const fixture = clientFor(normal);
  await fixture.client.load(id, key);
  await fixture.client.load(id, key);
  assert.equal(fixture.calls.length, 3);
  await fixture.client.load(id, 'b'.repeat(32));
  assert.equal(fixture.calls.length, 6);
  fixture.client.clearCache();
  await fixture.client.load(id, 'b'.repeat(32));
  assert.equal(fixture.calls.length, 9);
});
test('Recently played request failure preserves a usable lifetime library', async () => {
  const fixture = clientFor(url => {
    if (url.pathname.includes('GetRecentlyPlayedGames')) throw new Error('offline');
    return normal(url);
  });
  const result = await fixture.client.load(id, key);
  assert.equal(result.totalMinutes, 600);
  assert.equal(result.recentMinutes, null);
  assert.equal(fixture.destroyed(), 3);
});
test('Network errors never surface a credential-bearing URL', async () => {
  const fixture = clientFor(url => { throw new Error('failed ' + url.href); });
  await assert.rejects(fixture.client.load(id, key), error => !error.message.includes(key) && error.message.includes('连接 Steam'));
  assert.equal(fixture.destroyed(), 1);
});
test('Invalid keys and rate limiting have useful sanitized errors', async () => {
  for (const [status, phrase] of [[403, 'API 密钥'], [429, '频繁']]) {
    const fixture = clientFor(() => ({ responseCode: status, result: '' }));
    await assert.rejects(fixture.client.load(id, key), error => error.message.includes(phrase) && !error.message.includes(key));
    assert.equal(fixture.destroyed(), 1);
  }
});
test('Malformed Steam responses and nonexistent users are handled', async () => {
  for (const response of [{ responseCode: 200, result: '<html>' }, { responseCode: 200, result: '{}' }, json({ players: [] })]) {
    const fixture = clientFor(() => response);
    await assert.rejects(fixture.client.load(id, key));
    assert.equal(fixture.destroyed(), 1);
  }
});

function storeFor() {
  const tags = { ALIAS: 1, SECRET: 2, ACCESSIBILITY: 3, AUTH_TYPE: 4, SYNC_TYPE: 5, CONFLICT_RESOLUTION: 6, RETURN_TYPE: 7 };
  let record = null;
  let failRead = false;
  let failSave = false;
  let failClear = false;
  const asset = {
    Tag: tags, ReturnType: { ALL: 0 }, Accessibility: { DEVICE_UNLOCKED: 2 },
    AuthType: { NONE: 0 }, SyncType: { NEVER: 0 }, ConflictResolution: { OVERWRITE: 0 },
    async query() { if (failRead) throw { code: 24000001 }; if (!record) throw { code: 24000002 }; return [record]; },
    async add(attrs) { if (failSave) throw { code: 24000001 }; record = attrs; },
    async remove() { if (failClear) throw { code: 24000001 }; if (!record) throw { code: 24000002 }; record = null; }
  };
  const util = {
    TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } },
    TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder().decode(bytes) }) }
  };
  const Store = load('service/KeyStore.ets', 'KeyStore', { asset, util });
  return { store: new Store(), record: () => record, tags,
    failRead: () => { failRead = true; }, failSave: () => { failSave = true; }, failClear: () => { failClear = true; } };
}
test('Secure store supports missing key, save, replacement, read and deletion', async () => {
  const fixture = storeFor();
  assert.equal(await fixture.store.read(), '');
  await fixture.store.save(key);
  assert.equal(await fixture.store.read(), key);
  const attrs = fixture.record();
  assert.equal(attrs.get(fixture.tags.ACCESSIBILITY), 2);
  assert.equal(attrs.get(fixture.tags.SYNC_TYPE), 0);
  assert.equal(attrs.get(fixture.tags.CONFLICT_RESOLUTION), 0);
  await fixture.store.save('b'.repeat(32));
  assert.equal(await fixture.store.read(), 'b'.repeat(32));
  await fixture.store.clear();
  assert.equal(await fixture.store.read(), '');
  await fixture.store.clear();
});
test('Secure-store failures are reported and never fall back to plaintext storage', async () => {
  const reading = storeFor(); reading.failRead();
  await assert.rejects(reading.store.read(), error => error.message.includes('安全存储'));
  const saving = storeFor(); saving.failSave();
  await assert.rejects(saving.store.save(key), error => !error.message.includes(key));
  assert.equal(saving.record(), null);
  const clearing = storeFor(); await clearing.store.save(key); clearing.failClear();
  await assert.rejects(clearing.store.clear(), error => error.message.includes('删除'));
  assert.equal(await clearing.store.read(), key);
});


const familyToken = 'fixture_family_token_not_a_real_credential';
const otherId = '76561198000000001';
function familyResponder(url) {
  if (url.pathname.includes('GetFamilyGroupForUser')) return json({ family_groupid: '123456789012345678', is_not_member_of_any_group: false });
  if (url.pathname.includes('GetSharedLibraryApps')) return json({ owner_steamid: id, apps: [
    { appid: 730, name: 'CS2 duplicate', owner_steamids: [id, otherId], rt_playtime: 99999 },
    { appid: 500, name: 'Shared game', owner_steamids: [otherId], rt_playtime: 120, app_type: 1, exclude_reason: 0 },
    { appid: 500, name: 'Duplicate shared game', owner_steamids: [otherId], rt_playtime: 120 },
    { appid: 600, name: 'Excluded game', owner_steamids: [otherId], exclude_reason: 1 },
    { appid: 700, name: 'Tool', owner_steamids: [otherId], app_type: 2 }
  ] });
  return normal(url);
}

test('Family login accepts only HTTPS Steam hosts and parses serialized endpoint JSON', () => {
  for (const url of ['https://store.steampowered.com/login/', 'https://login.steampowered.com/jwt/finalizelogin', 'https://steamcommunity.com/']) assert.equal(family.isSteamLoginUrl(url), true);
  for (const url of ['http://store.steampowered.com/', 'https://steampowered.com.evil.example/', 'https://steampoweredXcom/', 'https://steampowered.com@evil.example/', 'https://evil.example/?url=https://steampowered.com/', 'javascript:alert(1)']) assert.equal(family.isSteamLoginUrl(url), false);
  const raw = JSON.stringify({ data: { webapi_token: familyToken } });
  assert.equal(family.extractFamilyToken(raw), familyToken);
  assert.equal(family.extractFamilyToken(JSON.stringify(raw)), familyToken);
  for (const raw of ['<html>Login</html>', '{}', '{"data":{"webapi_token":"tiny"}}', JSON.stringify({data:{webapi_token:'a'.repeat(9000)}})]) assert.throws(() => family.extractFamilyToken(raw));
});

test('Family games merge by appId, exclude unavailable apps and retain personal playtimes', async () => {
  const fixture = clientFor(familyResponder);
  const result = await fixture.client.load(id, key, familyToken);
  assert.equal(result.familyStatus, 'available');
  assert.equal(result.gameCount, 3);
  assert.equal(result.totalMinutes, 720);
  assert.equal(result.recentMinutes, 90);
  assert.equal(result.games.find(g => g.appId === 730).totalMinutes, 600);
  assert.equal(result.games.find(g => g.appId === 730).source, 'owned');
  assert.equal(result.games.find(g => g.appId === 500).source, 'family');
  assert.equal(result.games.find(g => g.appId === 500).recentMinutes, 0);
  assert.equal(fixture.calls.length, 5);
  const familyCalls = fixture.calls.filter(call => call.url.pathname.includes('IFamilyGroupsService'));
  for (const call of familyCalls) {
    assert.equal(call.url.origin, 'https://api.steampowered.com');
    assert.equal(call.url.searchParams.get('access_token'), familyToken);
    assert.equal(call.url.searchParams.has('key'), false);
  }
  assert.equal(familyCalls[1].url.searchParams.get('include_excluded'), 'false');
  assert.equal(familyCalls[1].url.searchParams.get('include_non_games'), 'false');
  assert.equal(familyCalls[1].url.searchParams.get('family_groupid'), '123456789012345678');
  assert.equal(fixture.destroyed(), 5);
});

test('Missing shared minutes stay unavailable and never use another member playtime', () => {
  const own = data.normalizeLibrary(player, { games: [{appid:1,playtime_forever:60}] }, {total_count:0}, 'now');
  const result = family.mergeFamilyLibrary(own, {apps:[{appid:2,owner_steamids:[otherId],rt_playtime:99999}]}, {total_count:0});
  assert.equal(result.games.find(g => g.appId === 2).totalMinutes, null);
  assert.equal(result.totalMinutes, null);
  assert.equal(result.gameCount, 2);
  assert.throws(() => family.mergeFamilyLibrary(own, {owner_steamid:otherId,apps:[]}, {total_count:0}), /不一致/);
});

test('Recent shared personal playtime and own games absent from personal response are merged', () => {
  const recent={games:[{appid:2,playtime_forever:80,playtime_2weeks:20}]};
  const own=data.normalizeLibrary(player,{game_count:0},recent,'now');
  const result=family.mergeFamilyLibrary(own,{apps:[{appid:2,owner_steamids:[otherId]},{appid:3,owner_steamids:[id]}]},recent);
  assert.equal(result.games.find(g=>g.appId===2).totalMinutes,80);
  assert.equal(result.games.find(g=>g.appId===2).recentMinutes,20);
  assert.equal(result.games.find(g=>g.appId===3).source,'owned');
  assert.equal(result.recentMinutes,20);
});

test('A family list does not conceal an unavailable personal library', () => {
  const own=data.normalizeLibrary(player,{}, {},'now');
  const result=family.mergeFamilyLibrary(own,{owner_steamid:id,apps:[{appid:2,owner_steamids:[otherId],rt_playtime:0}]},{});
  assert.equal(result.games.length,1);
  assert.equal(result.gameCount,null);
  assert.equal(result.totalMinutes,null);
  assert.equal(result.games[0].recentMinutes,null);
});

test('No-family and expired authorization preserve the usable personal library', async () => {
  for (const [response,status] of [[json({is_not_member_of_any_group:true}), 'none'], [{responseCode:403,result:''}, 'unavailable']]) {
    const fixture=clientFor(url=>url.pathname.includes('IFamilyGroupsService')?response:normal(url));
    const result=await fixture.client.load(id,key,familyToken);
    assert.equal(result.familyStatus,status);
    assert.equal(result.gameCount,2);
    assert.equal(result.totalMinutes,600);
    assert.equal(result.notices.join(' ').includes(familyToken),false);
    if(status==='unavailable') assert.match(result.notices.join(' '),/重新登录/);
  }
});

test('Family network failure and account mismatch return sanitized notices', async () => {
  for (const mode of ['network','account','missing']) {
    const fixture=clientFor(url=> {
      if(url.pathname.includes('GetSharedLibraryApps')) {
        if(mode==='network') throw new Error('failed '+url.href);
        if(mode==='account') return json({owner_steamid:otherId,apps:[]});
        return json({});
      }
      return familyResponder(url);
    });
    const result=await fixture.client.load(id,key,familyToken);
    assert.equal(result.familyStatus,'unavailable');
    assert.equal(result.games.length,2);
    assert.equal(result.notices.join(' ').includes(familyToken),false);
    assert.equal(result.notices.join(' ').includes(key),false);
  }
});

test('Family credentials and disabled family mode are part of cache identity', async () => {
  const fixture=clientFor(familyResponder);
  await fixture.client.load(id,key,familyToken);
  await fixture.client.load(id,key,familyToken);
  assert.equal(fixture.calls.length,5);
  const own=await fixture.client.load(id,key);
  assert.equal(own.games.length,2);
  assert.equal(fixture.calls.length,8);
  await fixture.client.load(id,key,familyToken+'changed');
  assert.equal(fixture.calls.length,13);
});

test('Family token and personal key use separate secure-store aliases', async () => {
  const records=new Map();
  const tags={ALIAS:1,SECRET:2,ACCESSIBILITY:3,AUTH_TYPE:4,SYNC_TYPE:5,CONFLICT_RESOLUTION:6,RETURN_TYPE:7};
  const alias=attrs=>new TextDecoder().decode(attrs.get(tags.ALIAS));
  const asset={Tag:tags,ReturnType:{ALL:0},Accessibility:{DEVICE_UNLOCKED:2},AuthType:{NONE:0},SyncType:{NEVER:0},ConflictResolution:{OVERWRITE:0},
    async add(attrs){records.set(alias(attrs),attrs);},
    async query(attrs){if(!records.has(alias(attrs)))throw {code:24000002};return [records.get(alias(attrs))];},
    async remove(attrs){records.delete(alias(attrs));}};
  const util={TextEncoder:class{encodeInto(value){return new TextEncoder().encode(value);}},TextDecoder:{create:()=>({decodeToString:bytes=>new TextDecoder().decode(bytes)})}};
  const Store=load('service/KeyStore.ets','KeyStore',{asset,util});
  const personal=new Store(), shared=new Store('steam_hours_family_token_v1');
  await personal.save(key); await shared.save(familyToken);
  assert.equal(await personal.read(),key);
  assert.equal(await shared.read(),familyToken);
  await shared.clear();
  assert.equal(await personal.read(),key);
  assert.equal(await shared.read(),'');
});


test('Malformed shared data is rejected before any partial merge', () => {
 const own=data.normalizeLibrary(player,{games:[{appid:1,playtime_forever:60}]},{total_count:0},'now');
 assert.throws(()=>family.mergeFamilyLibrary(own,{owner_steamid:id,apps:[{appid:2,rt_playtime:60},null]},{total_count:0}), /格式异常/);
 assert.equal(own.games.length,1);
 assert.equal(own.totalMinutes,60);
});

test('A successful family merge removes obsolete zero and missing-time notices', () => {
 const own=data.normalizeLibrary(player,{game_count:0},{total_count:0},'now');
 const result=family.mergeFamilyLibrary(own,{owner_steamid:id,apps:[{appid:2,owner_steamids:[otherId],rt_playtime:60}]},{total_count:0});
 assert.equal(result.totalMinutes,60);
 assert.equal(result.notices.some(n=>n.includes('所有已返回时长均为 0')),false);
 const missing=data.normalizeLibrary(player,{games:[{appid:3}]},{total_count:0},'now');
 family.mergeFamilyLibrary(missing,{owner_steamid:id,apps:[{appid:3,rt_playtime:60}]},{total_count:0});
 assert.equal(missing.totalMinutes,60);
 assert.equal(missing.notices.some(n=>n.includes('累计时长暂不可用')),false);
});

test('Steam nickname and best available profile avatar come from the queried real player', () => {
  for (const avatars of [{avatarfull:'https://avatars.steamstatic.com/full.jpg',avatarmedium:'medium'}, {avatarmedium:'https://avatars.steamstatic.com/medium.jpg'}, {avatar:'https://avatars.steamstatic.com/small.jpg'}]) {
    const result=data.normalizeLibrary({...player,personaname:'同步昵称',...avatars},{game_count:0},{total_count:0},'now');
    assert.equal(result.demo,false); assert.equal(result.player.name,'同步昵称');
    assert.equal(result.player.avatarUrl,avatars.avatarfull || avatars.avatarmedium || avatars.avatar);
  }
});
test('A mismatched player summary cannot replace the requested account identity',async()=>{
  const fixture=clientFor(url=>url.pathname.includes('GetPlayerSummaries')?json({players:[{steamid:'76561198000000001',personaname:'Other'}]}):normal(url));
  await assert.rejects(fixture.client.load(id,key),/不一致/);assert.equal(fixture.calls.length,1);assert.equal(fixture.destroyed(),1);
});