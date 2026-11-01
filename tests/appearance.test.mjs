import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const ets = '../harmony/entry/src/main/ets/';
const read = relative => readFileSync(new URL(ets + relative, import.meta.url), 'utf8')
  .replace(/^import[\s\S]*?;\r?\n/gm, '').replace(/\bexport /g, '');
const palette = read('model/Appearance.ets');
const service = palette + '\n' + read('service/AppearanceStore.ets');
const colors = runInNewContext(stripTypeScriptTypes(palette) + '\n({ colorsFor, normalizeAppearance })');
const enums = { ColorMode: { COLOR_MODE_LIGHT: 1, COLOR_MODE_DARK: 0 } };
function load(globals) {
  return runInNewContext(stripTypeScriptTypes(service) + '\n({ AppearanceStore, applyAppearance })',
    { ConfigurationConstant: enums, console: { warn() {} }, ...globals });
}

test('A saved day/night choice survives a new store without changing account or credential settings', async () => {
  const values = new Map([['account', '76561198000000000'], ['rememberKey', true], ['includeFamily', true]]);
  let flushed = 0;
  const preferences = { getPreferences: async () => ({
    get: async (key, fallback) => values.has(key) ? values.get(key) : fallback,
    put: async (key, value) => values.set(key, value), flush: async () => { flushed += 1; }
  }) };
  const { AppearanceStore } = load({ preferences });
  const context = {};
  assert.equal(await new AppearanceStore().read(context), 'night');
  for (const mode of ['day', 'night']) {
    await new AppearanceStore().save(context, mode);
    assert.equal(await new AppearanceStore().read(context), mode);
  }
  assert.equal(flushed, 2);
  assert.equal(values.get('account'), '76561198000000000');
  assert.equal(values.get('rememberKey'), true);
  assert.equal(values.get('includeFamily'), true);
  assert.deepEqual([...values.keys()].sort(), ['account', 'appearanceMode', 'includeFamily', 'rememberKey']);
});

test('Invalid preferences and failed reads use the default; failed writes remain visible to the UI', async () => {
  assert.equal(colors.normalizeAppearance('unknown'), 'night');
  assert.equal(colors.normalizeAppearance('day'), 'day');
  const { AppearanceStore } = load({ preferences: { getPreferences: async () => { throw new Error('Storage unavailable'); } } });
  const store = new AppearanceStore();
  assert.equal(await store.read({}), 'night');
  await assert.rejects(store.save({}, 'day'), /Storage unavailable/);
});

test('Both palettes keep readable text, secondary labels and actions on their painted surfaces', () => {
  const luminance = hex => {
    const rgb = hex.slice(1).match(/../g).map(value => parseInt(value, 16) / 255)
      .map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
    return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
  };
  for (const mode of ['day', 'night']) {
    const palette = colors.colorsFor(mode);
    for (const [foreground, background] of [
      ['text', 'background'], ['text', 'surface'], ['text', 'stats'], ['text', 'settings'],
      ['secondary', 'surface'], ['secondary', 'stats'], ['body', 'control'],
      ['primaryText', 'primary'], ['dangerText', 'dangerBackground'], ['success', 'stats'],
      ['placeholder', 'input'], ['muted', 'background']
    ]) {
      const a = luminance(palette[foreground]); const b = luminance(palette[background]);
      const contrast = (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
      assert.ok(contrast >= 4.5, mode + ': ' + foreground + '/' + background + ' contrast ' + contrast);
    }
  }
});

test('Native color mode and system bars match both palettes; an optional window failure is contained', async () => {
  const received = [];
  const context = { getApplicationContext: () => ({ setColorMode: mode => received.push(['mode', mode]) }) };
  const { applyAppearance } = load({ window: { getLastWindow: async () => ({
    setWindowLayoutFullScreen: async value => received.push(['layout', value]),
    setWindowSystemBarProperties: async values => received.push(['bars', values]),
    setWindowBackgroundColor: () => { throw new Error('Unsupported window background API'); }
  }) } });
  for (const mode of ['day', 'night']) {
    await applyAppearance(context, mode);
    const expected = colors.colorsFor(mode);
    const [, bars] = received.at(-1);
    assert.equal(bars.statusBarColor, '#00000000');
    assert.equal(bars.navigationBarColor, '#00000000');
    assert.equal(received.findLast(row => row[0] === 'layout')[1], false);
    assert.equal(bars.statusBarContentColor, expected.text);
    assert.equal(bars.navigationBarContentColor, expected.text);
    assert.equal(received.findLast(row => row[0] === 'mode')[1], mode === 'day' ? 1 : 0);
  }
  const failing = load({ window: { getLastWindow: async () => { throw new Error('No window'); } } });
  await assert.doesNotReject(failing.applyAppearance({ getApplicationContext() { throw new Error('No context'); } }, 'day'));
});


test('A failed native safe-layout request preserves themed opaque system bars and contains the failure', async () => {
  for (const mode of ['day', 'night']) {
    let properties;
    const { applyAppearance } = load({ window: { getLastWindow: async () => ({
      setWindowLayoutFullScreen: async () => { throw new Error('layout unavailable'); },
      setWindowSystemBarProperties: async values => { properties = values; },
      setWindowBackgroundColor() {}
    }) } });
    await assert.doesNotReject(applyAppearance({ getApplicationContext: () => ({ setColorMode() {} }) }, mode));
    const expected = colors.colorsFor(mode);
    assert.equal(properties.statusBarColor, expected.background); assert.equal(properties.navigationBarColor, expected.background);
    assert.equal(properties.statusBarContentColor, expected.text); assert.equal(properties.navigationBarContentColor, expected.text);
  }
});

test('Rejected system-bar configuration cannot interrupt appearance switching or cause an unhandled promise', async () => {
  const appliedModes = [];
  const { applyAppearance } = load({ window: { getLastWindow: async () => ({
    setWindowLayoutFullScreen: async () => {},
    setWindowSystemBarProperties: async () => { throw new Error('bars unavailable'); }
  }) } });
  for (const mode of ['day', 'night']) {
    await assert.doesNotReject(applyAppearance({ getApplicationContext: () => ({ setColorMode: value => appliedModes.push(value) }) }, mode));
  }
  assert.deepEqual(appliedModes, [1, 0]);
});
