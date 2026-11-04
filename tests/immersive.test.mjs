import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../harmony/entry/src/main/ets/components/ImmersiveStyle.ets', import.meta.url), 'utf8')
  .replace(/^import[\s\S]*?;\r?\n/gm, '').replace(/\bexport /g, '');
const palette = readFileSync(new URL('../harmony/entry/src/main/ets/model/Appearance.ets', import.meta.url), 'utf8').replaceAll('export ', '');
const code = stripTypeScriptTypes(palette + '\n' + source) + '\n({ immersiveFor, floatingActionBarWidth })';
function theme(sdkApiVersion, material, mode = 'night') {
  const deviceInfo = { sdkApiVersion, apiAvailable: () => sdkApiVersion >= 26 };
  return runInNewContext(code, { deviceInfo, uiMaterial: material, BarStyle: { STANDARD: 0, STACK: 1 } }).immersiveFor(mode);
}
function applyAll(value, control) {
  for (const modifier of [value.button, value.primary, value.bottomButton, value.bottomPrimary, value.danger, value.select, value.toggle, value.tabsStyle(true), value.tabsStyle(false)]) modifier.applyNormalAttribute(control);
}
const unavailableControl = new Proxy({}, { get() { throw new Error('New UI API called on fallback'); } });

test('API 12 does not access material APIs or override the original button foreground', () => {
  const unavailableMaterial = new Proxy({}, { get() { throw new Error('New material API called on API 12'); } });
  const value = theme(12, unavailableMaterial);
  assert.equal(value.enabled, false);
  applyAll(value, unavailableControl);
  assert.equal(value.titleOptions().barStyle, 0);
  assert.equal('systemMaterial' in value.titleOptions(), false);
});

test('An unsupported API 26 device retains the original controls', () => {
  const value = theme(26, { isImmersiveMaterialSupported: () => false });
  assert.equal(value.enabled, false);
  applyAll(value, unavailableControl);
});

test('A capability error or partial material construction falls back without a startup crash', () => {
  for (const material of [
    { isImmersiveMaterialSupported() { throw new Error('Capability unavailable'); } },
    { isImmersiveMaterialSupported: () => true, ImmersiveStyle: { THIN: 1, REGULAR: 2 },
      ImmersiveMaterial: class { constructor(options) { if (options.style === 2) throw new Error('Material unavailable'); } } }
  ]) {
    const value = theme(26, material);
    assert.equal(value.enabled, false);
    applyAll(value, unavailableControl);
    assert.equal('systemMaterial' in value.titleOptions(), false);
  }
});

test('Supported devices reuse materials and style the dropdown independently of the select button', () => {
  let created = 0;
  const value = theme(26, {
    isImmersiveMaterialSupported: () => true, ImmersiveStyle: { THIN: 1, REGULAR: 2, THICK: 3 },
    ImmersiveMaterial: class { constructor(options) { this.options = options; created += 1; } }
  });
  const calls = [];
  const control = {
    systemMaterial(material) { calls.push(['surface', material]); return this; },
    menuSystemMaterial(material) { calls.push(['menu', material]); return this; },
    fontColor(color) { calls.push(['text', color]); return this; },
    divider() { return this; }, barFloatingStyle(options) { calls.push(['floating', options]); return this; },
    optionFontColor(color) { calls.push(['option', color]); return this; }
  };
  assert.equal(value.enabled, true);
  value.select.applyNormalAttribute(control);
  assert.notEqual(calls[0][1], calls[1][1]);
  value.primary.applyNormalAttribute(control);
  assert.equal(calls.findLast(call => call[0] === 'text')[1], '#10182D');
  const count = created;
  applyAll(value, control);
  applyAll(value, control);
  assert.equal(created, count);
  assert.equal(value.titleOptions().barStyle, 1);
  assert.ok(value.titleOptions().systemMaterial);
});

test('Switching material themes reuses each variant and keeps day foregrounds dark', () => {
  let created = 0;
  const deviceInfo = { sdkApiVersion: 26, apiAvailable: () => true };
  const uiMaterial = {
    isImmersiveMaterialSupported: () => true, ImmersiveStyle: { THIN: 1, REGULAR: 2, THICK: 3 },
    ImmersiveMaterial: class { constructor(options) { this.options = options; created += 1; } }
  };
  const { immersiveFor } = runInNewContext(code, { deviceInfo, uiMaterial, BarStyle: { STANDARD: 0, STACK: 1 } });
  const day = immersiveFor('day');
  const night = immersiveFor('night');
  const count = created;
  assert.equal(day, immersiveFor('day'));
  assert.equal(night, immersiveFor('night'));
  assert.notEqual(day, night);
  assert.notEqual(day.titleOptions().systemMaterial.options.materialColor, night.titleOptions().systemMaterial.options.materialColor);
  let foreground;
  day.button.applyNormalAttribute({ systemMaterial() { return this; }, fontColor(color) { foreground = color; return this; } });
  assert.equal(foreground, '#334563');
  assert.equal(created, count);
});

test('Official bottom bar restores when the keyboard opens and does not create new materials', () => {
  const value = theme(26, {
    isImmersiveMaterialSupported: () => true, ImmersiveStyle: { THIN: 1, REGULAR: 2, THICK: 3 },
    ImmersiveMaterial: class { constructor(options) { this.options = options; } }
  });
  const calls = [];
  const tabs = { divider() { return this; }, barFloatingStyle(options) { calls.push(options); return this; } };
  value.tabsStyle(true).applyNormalAttribute(tabs);
  const initial = calls[0];
  assert.ok(initial.systemMaterial);
  assert.equal(initial.maskColor, '#00000000');
  assert.equal(initial.maskHeight, 0);
  assert.equal(initial.barSideMargin, 20);
  assert.equal(initial.barBottomMargin, 16);
  value.tabsStyle(false).applyNormalAttribute(tabs);
  assert.equal(calls[1], undefined);
  value.tabsStyle(true).applyNormalAttribute(tabs);
  assert.equal(calls[2].systemMaterial, initial.systemMaterial);
  assert.equal(calls[2].maskColor, '#00000000');
  assert.equal(calls[2].maskHeight, 0);
  assert.equal(value.titleOptions().backgroundEffect.radius, 32);
  assert.equal(value.titleOptions().scrollEffectOptions, undefined);
});

test('Custom material tint/foreground follow the palette and each mode reuses its current custom material', () => {
  const created = [];
  const instance = runInNewContext(code, {
    deviceInfo: { sdkApiVersion: 26, apiAvailable: () => true },
    uiMaterial: { isImmersiveMaterialSupported: () => true, ImmersiveStyle: { THIN: 1, REGULAR: 2, THICK: 3 },
      ImmersiveMaterial: class { constructor(options) { this.options = options; created.push(options); } } },
    BarStyle: { STANDARD: 0, STACK: 1 },
  });
  const first = instance.immersiveFor('night', '#FFFFFF');
  const count = created.length;
  assert.equal(instance.immersiveFor('night', '#FFFFFF'), first); assert.equal(created.length, count);
  const calls = []; first.primary.applyNormalAttribute({
    systemMaterial(value) { calls.push(value.options.materialColor); return this; },
    fontColor(value) { calls.push(value); return this; }
  });
  assert.deepEqual(calls, ['#E0FFFFFF', '#000000']);
  assert.notEqual(instance.immersiveFor('night', '#000000'), first);
  assert.notEqual(instance.immersiveFor('day', '#FFFFFF'), first);
  assert.notEqual(instance.immersiveFor('night'), first);
});

test('Official floating width follows phone/tablet viewport changes and reserves both side margins', () => {
  const created = [];
  const api = runInNewContext(code, {
    deviceInfo: { sdkApiVersion: 26, apiAvailable: () => true },
    uiMaterial: { isImmersiveMaterialSupported: () => true, ImmersiveStyle: { THIN: 1, REGULAR: 2, THICK: 3 },
      ImmersiveMaterial: class { constructor(options) { this.options = options; created.push(options); } } },
    BarStyle: { STANDARD: 0, STACK: 1 },
  });
  const value = api.immersiveFor('night');
  const count = created.length; let initialMaterial;
  for (const viewport of [320, 360, 373.33, 412, 768, 1280]) {
    let floating;
    value.tabsStyle(true, viewport).applyNormalAttribute({ divider() { return this; }, barFloatingStyle(style) { floating = style; } });
    for (const breakpoint of ['smallBarWidth', 'mediumBarWidth', 'largeBarWidth']) {
      assert.equal(floating.barWidth[breakpoint], viewport - 40);
      assert.ok(floating.barWidth[breakpoint] > 0 && floating.barWidth[breakpoint] < viewport);
    }
    assert.equal(floating.barSideMargin, 20);
    initialMaterial ??= floating.systemMaterial;
    assert.equal(floating.systemMaterial, initialMaterial);
  }
  assert.equal(created.length, count);
});

test('Missing/invalid viewport sizes have a stable positive fallback; keyboard hiding still cancels floating style', () => {
  const api = runInNewContext(code, {
    deviceInfo: { sdkApiVersion: 26, apiAvailable: () => true },
    uiMaterial: { isImmersiveMaterialSupported: () => true, ImmersiveStyle: { THIN: 1, REGULAR: 2, THICK: 3 }, ImmersiveMaterial: class {} },
    BarStyle: { STANDARD: 0, STACK: 1 },
  });
  for (const size of [0, -1, NaN, Infinity]) assert.equal(api.floatingActionBarWidth(size), 320);
  assert.equal(api.floatingActionBarWidth(1), 1);
  let received = 'pending';
  api.immersiveFor('night').tabsStyle(false, 412).applyNormalAttribute({ divider() { return this; }, barFloatingStyle(style) { received = style; } });
  assert.equal(received, undefined);
});

test('Floating capsule and both action variants disable material shadows in day/night/custom themes', () => {
  for (const mode of ['day', 'night']) {
    const api = runInNewContext(code, {
      deviceInfo: { sdkApiVersion: 26, apiAvailable: () => true },
      uiMaterial: { isImmersiveMaterialSupported: () => true, ImmersiveStyle: { THIN: 1, REGULAR: 2, THICK: 3 },
        ImmersiveMaterial: class { constructor(options) { this.options = options; } } },
      BarStyle: { STANDARD: 0, STACK: 1 },
    });
    for (const color of ['', '#00A36C']) {
      const value = api.immersiveFor(mode, color); const surfaces = [];
      value.tabsStyle(true, 360).applyNormalAttribute({ divider() { return this; }, barFloatingStyle(style) { surfaces.push(style.systemMaterial.options); } });
      for (const action of [value.bottomButton, value.bottomPrimary]) {
        action.applyNormalAttribute({ systemMaterial(material) { surfaces.push(material.options); return this; }, fontColor() { return this; } });
      }
      assert.equal(surfaces.length, 3);
      assert.ok(surfaces.every(surface => surface.applyShadow === false));
      assert.ok(surfaces.every(surface => surface.interactive === true && surface.lightEffect));
      assert.equal(value.titleOptions().systemMaterial.options.applyShadow, false);
    }
  }
});

test('Both themes cache one native backdrop effect without the fling-sensitive scroll effect', () => {
  for (const mode of ['day', 'night']) {
    const value = theme(26, { isImmersiveMaterialSupported: () => true,
      ImmersiveStyle: { THIN: 1, REGULAR: 2, THICK: 3 },
      ImmersiveMaterial: class { constructor(options) { this.options = options; } } }, mode);
    const options = value.titleOptions();
    for (let i = 0; i < 100; i++) assert.equal(value.titleOptions(), options);
    assert.equal(options.backgroundBlurStyle, undefined);
    assert.equal(options.backgroundEffect.radius, 32);
    assert.equal(options.backgroundEffect.saturation, 1.15);
    assert.match(options.backgroundEffect.color, /^#1A[0-9A-Fa-f]{6}$/);
    assert.equal(options.backgroundEffect, value.titleOptions().backgroundEffect);
    assert.equal(options.scrollEffectOptions, undefined);
    assert.equal(options.backgroundColor, '#00000000');
    assert.equal(options.barStyle, 1);
    assert.ok(options.systemMaterial);
    assert.equal(options.systemMaterial.options.applyShadow, false);
  }
});
 test('Fallback title configuration is also stable and preserves the day/night background',()=>{for(const mode of ['day','night']){const value=theme(12,{},mode);assert.equal(value.titleOptions(),value.titleOptions());assert.equal(value.titleOptions().barStyle,0);assert.equal(value.titleOptions().scrollEffectOptions,undefined);}});

 test('Floating style removes the one-vp mask and clears the divider after both show and hide updates',()=>{const value=theme(26,{isImmersiveMaterialSupported:()=>true,ImmersiveStyle:{THIN:1,REGULAR:2,THICK:3},ImmersiveMaterial:class{constructor(options){this.options=options;}}});for(const visible of [true,false]){const trace=[];value.tabsStyle(visible).applyNormalAttribute({barFloatingStyle:style=>{trace.push(['floating',style]);},divider:style=>trace.push(['divider',style])});assert.equal(trace[0][0],'floating');assert.equal(trace[1][0],'divider');assert.equal(trace[1][1].strokeWidth,0);assert.equal(trace[1][1].color,'#00000000');if(visible){assert.equal(trace[0][1].maskHeight,0);assert.equal(trace[0][1].maskColor,'#00000000');assert.ok(trace[0][1].systemMaterial);}}});
