import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const read = path => readFileSync(new URL('../harmony/entry/src/main/ets/' + path, import.meta.url), 'utf8')
  .replace(/^import[\s\S]*?;\r?\n/gm, '').replace(/\bexport /g, '');
const palette = read('model/Appearance.ets');
const code = stripTypeScriptTypes(palette + '\n' + read('service/PersonalizationStore.ets')) +
  '\n({ PersonalizationStore, colorsFor, colorContrast, normalizeThemeColor, normalizeBackgroundOpacity, normalizePanelTransparency, transparentPanelColor })';
const context = { filesDir: '/sandbox/files' };
const oldPath = context.filesDir + '/appearance/background-1-a.jpg';

function harness(config = {}) {
  const values = new Map([['account', '76561198000000000'], ['rememberKey', true], ['includeFamily', true],
    ['backgroundPath', oldPath], ...Object.entries(config.values ?? {})]);
  const files = new Map([[oldPath, new Uint8Array([1, 2])]]);
  const handles = new Map(); const released = []; const removed = []; const selections = [];
  let next = 100; let failFlush = config.failFlush ?? 0; let size = config.size ?? 100;
  const preferences = { getPreferences: async () => {
    if (config.readFailure) throw new Error('unavailable');
    return { get: async (key, fallback) => values.has(key) ? values.get(key) : fallback,
      put: async (key, value) => values.set(key, value), flush: async () => {
        if (failFlush > 0) { failFlush--; throw new Error('flush failure'); }
      } };
  } };
  const nativeFs = {
    OpenMode: { READ_ONLY: 0, CREATE: 1, READ_WRITE: 2, TRUNC: 4 },
    accessSync: path => files.has(path) || path === context.filesDir + '/appearance',
    mkdir: async () => {},
    open: async (path, flags) => {
      if (flags !== 0) files.set(path, new Uint8Array());
      const file = { fd: ++next }; handles.set(file.fd, path); return file;
    },
    close: async file => { assert.ok(handles.delete(file.fd)); },
    stat: async () => ({ size }),
    write: async (fd, data) => {
      const path = handles.get(fd); const existing = files.get(path);
      const chunk = new Uint8Array(data).slice(0, config.shortWrite ? 4 : data.byteLength);
      const result = new Uint8Array(existing.length + chunk.length); result.set(existing); result.set(chunk, existing.length);
      files.set(path, result); return chunk.length;
    },
    unlink: async path => { removed.push(path); files.delete(path); }
  };
  const image = {
    createImageSource: fd => ({
      getImageInfo: async () => ({ size: config.dimensions ?? { width: 6000, height: 4000 } }),
      createPixelMap: async options => {
        if (config.decodeFailure) throw new Error('bad image');
        selections.push(['decode', options]); return { release: async () => released.push('pixels') };
      },
      release: async () => released.push('source')
    }),
    createImagePacker: () => ({
      packing: async (pixels, options) => { selections.push(['pack', options]); return new Uint8Array(17).buffer; },
      release: async () => released.push('packer')
    })
  };
  const photoAccessHelper = {
    PhotoViewMIMETypes: { IMAGE_TYPE: 'image/*' }, PhotoSelectOptions: class {},
    PhotoViewPicker: class { async select(options) { selections.push(['picker', options]);
      return { photoUris: config.cancel ? [] : ['file://media/Photo/picked.jpg'] }; } }
  };
  const api = runInNewContext(code, { preferences, fs: nativeFs, image, photoAccessHelper });
  return { ...api, values, files, handles, removed, released, selections, store: new api.PersonalizationStore() };
}

test('Custom color saves independently of account/credential preferences; invalid input is not committed', async () => {
  const h = harness();
  assert.equal(await h.store.saveColor(context, ' #abC123 '), '#ABC123');
  assert.equal((await h.store.read(context)).themeColor, '#ABC123');
  await assert.rejects(h.store.saveColor(context, '#12345'), /RRGGBB/);
  assert.equal(h.values.get('themeColor'), '#ABC123');
  assert.equal(h.values.get('account'), '76561198000000000');
  assert.equal(h.values.get('rememberKey'), true); assert.equal(h.values.get('includeFamily'), true);
  assert.equal(await h.store.saveColor(context, ''), '');
});

test('Opacity is bounded; missing images and paths outside the dedicated sandbox are never restored', async () => {
  const h = harness({ values: { backgroundPath: '/sandbox/files/private-key', backgroundOpacity: 9 } });
  assert.equal((await h.store.read(context)).backgroundPath, '');
  assert.equal((await h.store.read(context)).backgroundOpacity, 1);
  assert.equal(await h.store.saveOpacity(context, -1), 0.08);
  assert.equal(await h.store.saveOpacity(context, NaN), 0.22);
  h.values.set('backgroundPath', context.filesDir + '/appearance/background-2-b.jpg');
  assert.equal((await h.store.read(context)).backgroundPath, '');
});

test('Cancelling the official image picker leaves the previous background and preferences unchanged', async () => {
  const h = harness({ cancel: true });
  assert.equal(await h.store.chooseBackground(context), null);
  assert.equal(h.values.get('backgroundPath'), oldPath);
  assert.equal(h.files.size, 1); assert.equal(h.handles.size, 0); assert.equal(h.removed.length, 0);
});

test('Selected image is decoded at a bounded size, fully written despite short writes, and restored on next launch', async () => {
  const h = harness({ shortWrite: true });
  const path = await h.store.chooseBackground(context);
  assert.match(path, /\/appearance\/background-\d+-[0-9a-f]+\.jpg$/);
  assert.equal(h.files.get(path).length, 17); assert.equal(h.files.has(oldPath), false);
  assert.equal((await h.store.read(context)).backgroundPath, path);
  assert.equal(h.handles.size, 0); assert.deepEqual(h.released.sort(), ['packer', 'pixels', 'source']);
  const picker = h.selections.find(v => v[0] === 'picker')[1];
  assert.equal(picker.MIMEType, 'image/*'); assert.equal(picker.maxSelectNumber, 1);
  const decode = h.selections.find(v => v[0] === 'decode')[1];
  assert.equal(decode.desiredSize.width, 2560); assert.equal(decode.desiredSize.height, 1707);
});

test('A failed preference flush restores the old path, removes only the uncommitted new image and releases handles', async () => {
  const h = harness({ failFlush: 1 });
  await assert.rejects(h.store.chooseBackground(context), /未能保存/);
  assert.equal(h.values.get('backgroundPath'), oldPath); assert.equal(h.files.has(oldPath), true);
  assert.equal(h.files.size, 1); assert.equal(h.handles.size, 0);
  assert.equal(h.removed.includes(oldPath), false);
});

test('An undecodable image cannot replace the old background and its input handle/source are released', async () => {
  const h = harness({ decodeFailure: true });
  await assert.rejects(h.store.chooseBackground(context), /bad image/);
  assert.equal(h.values.get('backgroundPath'), oldPath); assert.equal(h.files.size, 1);
  assert.equal(h.handles.size, 0); assert.deepEqual(h.released, ['source']);
});

test('Oversized files or pixel dimensions are rejected before allocating a pixel map', async () => {
  for (const config of [{ size: 51 * 1024 * 1024 }, { dimensions: { width: 20000, height: 20000 } }]) {
    const h = harness(config); await assert.rejects(h.store.chooseBackground(context));
    assert.equal(h.selections.some(v => v[0] === 'decode'), false);
    assert.equal(h.values.get('backgroundPath'), oldPath); assert.equal(h.handles.size, 0);
  }
});

test('Background reset preserves the old image on failed commit and never deletes arbitrary preference paths', async () => {
  const failing = harness({ failFlush: 1 });
  await assert.rejects(failing.store.removeBackground(context));
  assert.equal(failing.files.has(oldPath), true); assert.equal(failing.values.get('backgroundPath'), oldPath);
  const h = harness(); await h.store.removeBackground(context);
  assert.equal(h.values.get('backgroundPath'), ''); assert.equal(h.files.has(oldPath), false);
  const unsafe = harness({ values: { backgroundPath: '/sandbox/files/private-key' } });
  await unsafe.store.removeBackground(context); assert.equal(unsafe.removed.length, 0);
});

test('Unavailable preference storage does not prevent default appearance startup', async () => {
  const h = harness({ readFailure: true }); const value = await h.store.read(context);
  assert.equal(value.themeColor, ''); assert.equal(value.backgroundPath, ''); assert.equal(value.backgroundOpacity, 0.22);
});

test('Extreme and preset custom colors retain readable primary action text and accent labels in both modes', () => {
  const h = harness();
  for (const mode of ['day', 'night']) for (const color of ['#000000', '#FFFFFF', '#FF0000', '#00FF00', '#0000FF', '#808080', '#4963C9', '#7C4DCC', '#21866C', '#C04C65', '#AF701D']) {
    const p = h.colorsFor(mode, color); assert.equal(p.primary, color);
    assert.ok(h.colorContrast(p.primaryText, p.primary) >= 4.5, mode + color + ' primary');
    for (const background of ['settings', 'stats', 'surface', 'detail']) {
      assert.ok(h.colorContrast(p.accent, p[background]) >= 4.5, mode + color + background);
    }
    assert.ok(h.colorContrast(p.iconText, p.control) >= 4.5);
  }
});


test('Foreground blur defaults, bounds and saved disabled state survive recreation without changing other settings', async () => {
  const h = harness(); assert.equal((await h.store.read(context)).foregroundBlurStrength, 0.4);
  assert.equal(await h.store.saveForegroundBlur(context, 2), 1);
  assert.equal(await new h.PersonalizationStore().read(context).then(value => value.foregroundBlurStrength), 1);
  assert.equal(await h.store.saveForegroundBlur(context, -1), 0);
  assert.equal((await h.store.read(context)).foregroundBlurStrength, 0);
  assert.equal(await h.store.saveForegroundBlur(context, NaN), 0.4);
  assert.equal(h.values.get('backgroundPath'), oldPath);
  assert.equal(h.values.get('account'), '76561198000000000'); assert.equal(h.values.has('themeColor'), false);
});

test('Failed blur and color saves roll back in-memory preferences so later flushes cannot commit failed changes', async () => {
  for (const [key, action, original] of [
    ['foregroundBlurStrength', h => h.store.saveForegroundBlur(context, 1), 0.25],
    ['themeColor', h => h.store.saveColor(context, '#FFFFFF'), '#123456']]) {
    const h = harness({ failFlush: 1, values: { [key]: original } });
    await assert.rejects(action(h), /未能保存/); assert.equal(h.values.get(key), original);
    await h.store.saveOpacity(context, 0.3); assert.equal(h.values.get(key), original);
    assert.equal(h.values.get('backgroundPath'), oldPath); assert.equal(h.removed.length, 0);
  }
});

test('One hundred percent background opacity survives a new store without being reduced to the previous 45 percent cap',async()=>{const h=harness();assert.equal(await h.store.saveOpacity(context,1),1);const fresh=new h.PersonalizationStore();assert.equal((await fresh.read(context)).backgroundOpacity,1);assert.equal(await h.store.saveOpacity(context,0.72),0.72);assert.equal((await fresh.read(context)).backgroundOpacity,0.72);});


test('Card transparency upgrades default to 25 percent and all saved endpoints restore independently', async () => {
  const h=harness(); assert.equal((await h.store.read(context)).panelTransparency,0.25);
  for(const [input,expected] of [[0,0],[0.7,0.7],[1,1],[-1,0],[8,1],[NaN,0.25],[Infinity,0.25]]) {
    assert.equal(await h.store.savePanelTransparency(context,input),expected);
    assert.equal((await new h.PersonalizationStore().read(context)).panelTransparency,expected);
  }
  assert.equal(h.values.get('account'),'76561198000000000'); assert.equal(h.values.get('rememberKey'),true);
  assert.equal(h.values.get('backgroundPath'),oldPath); assert.equal(h.values.has('backgroundOpacity'),false);
  assert.equal(h.values.has('foregroundBlurStrength'),false); assert.equal(h.values.has('themeColor'),false);
  assert.equal((await harness({readFailure:true}).store.read(context)).panelTransparency,0.25);
});

test('Card alpha preserves RGB and existing alpha in both themes, without mutating the palette', () => {
  const h=harness();
  assert.equal(h.transparentPanelColor('#aBc123',0),'#FFABC123');
  assert.equal(h.transparentPanelColor('#FFFFFF',0.25),'#BFFFFFFF');
  assert.equal(h.transparentPanelColor('#80ABC123',0.5),'#40ABC123');
  for(const mode of ['day','night']) {
    const palette=h.colorsFor(mode,'#FF0000'); const original=JSON.stringify(palette);
    for(const key of ['surface','detail','stats','heroEnd','selectedSurface','edge','shadow','rowShadow']) {
      assert.equal(h.transparentPanelColor(palette[key],1).slice(0,3),'#00');
      assert.equal(h.transparentPanelColor(palette[key],1).slice(-6),palette[key].slice(-6).toUpperCase());
    }
    assert.equal(JSON.stringify(palette),original);
  }
});

test('A failed card transparency flush restores preferences before later unrelated saves', async () => {
  for(const original of [0,0.35,1]) {
    const h=harness({failFlush:1,values:{panelTransparency:original}});
    await assert.rejects(h.store.savePanelTransparency(context,0.8),/未能保存/);
    assert.equal(h.values.get('panelTransparency'),original);
    await h.store.saveOpacity(context,0.5);
    assert.equal((await h.store.read(context)).panelTransparency,original);
    assert.equal(h.removed.length,0);
  }
});

test('EntryAbility restores saved card transparency before initial content rendering', async () => {
  const source=read('entryability/EntryAbility.ets').replace('export default class EntryAbility','class EntryAbility').replace('default class EntryAbility','class EntryAbility');
  const events=[]; const api=runInNewContext(stripTypeScriptTypes(source)+'\n;({EntryAbility})',{
    PrivacyStore:class {async read(){return 'granted';}}, LocalDataCleaner:class {}, privacyAccess:{setAllowed(){}},
    UIAbility:class {},AppearanceStore:class {async read(){return 'day';}},
    PersonalizationStore:class {async read(){return {themeColor:'',backgroundPath:'',backgroundOpacity:0.22,foregroundBlurStrength:0.4,panelTransparency:0.65};}},
    AppStorage:{setOrCreate:(key,value)=>events.push([key,value])},applyAppearance:()=>{},console
  });
  const ability=new api.EntryAbility();ability.context={};
  await ability.loadMainPage({loadContent:()=>events.push(['render'])});
  assert.equal(events.find(row=>row[0]==='panelTransparency')[1],0.65);
  assert.ok(events.findIndex(row=>row[0]==='panelTransparency')<events.findIndex(row=>row[0]==='render'));
});
