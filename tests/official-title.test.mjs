import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';
const source = readFileSync(new URL('../harmony/entry/src/main/ets/components/OfficialTitleStyle.ets', import.meta.url), 'utf8').replace(/^import[^\n]*\n/gm, '').replace(/\bexport /g, '');
function harness(sdk = 26, capability = true, available = true) {
  let reads = 0;
  const material = { MaterialType: { ADAPTIVE: 100 }, MaterialLevel: { ADAPTIVE: 10 } };
  const api = runInNewContext(stripTypeScriptTypes(source) + '\n;({ OfficialTitleStyle })', {
    deviceInfo: { sdkApiVersion: sdk, apiAvailable: () => available }, canIUse: () => capability,
    hdsMaterial: new Proxy(material, { get(target, key) { reads++; if (sdk < 26) throw Error('New API accessed'); return target[key]; } }),
    HdsScrollEffectType: { IMMERSIVE_GRADIENT_BLUR: 3 }
  });
  return { value: new api.OfficialTitleStyle(), reads: () => reads };
}
test('Old SDKs, unavailable API and missing HDS capability never read material APIs', () => {
  for (const config of [[12], [18], [23], [25], [26, false], [26, true, false]]) {
    const h = harness(...config); assert.equal(h.value.supported, false);
    assert.equal(h.value.options(), undefined); assert.equal(h.reads(), 0);
  }
});
test('Current HDS uses the official immersive gradient and adaptive material, with no scroll-phase filter toggle', () => {
  const h = harness(); assert.equal(h.value.supported, true); const options = h.value.options();
  assert.equal(options.scrollEffectOpts.scrollEffectType, 3);
  assert.equal(options.scrollEffectOpts.enableScrollEffect, false);
  assert.equal(options.systemMaterialEffect.materialType, 100);
  assert.equal(options.systemMaterialEffect.materialLevel, 10);
  assert.equal(options.originalStyle, undefined); assert.equal(options.scrollEffectStyle, undefined);
  for (let i = 0; i < 100; i++) assert.equal(h.value.options(), options);
  assert.equal(h.reads(), 2);
});
test('Capability errors cannot prevent the legacy page from opening', () => {
  const api = runInNewContext(stripTypeScriptTypes(source) + '\n;({ OfficialTitleStyle })', {
    deviceInfo: { sdkApiVersion: 26, apiAvailable() { throw Error('Unavailable'); } }
  });
  const value = new api.OfficialTitleStyle(); assert.equal(value.supported, false); assert.equal(value.options(), undefined);
});
