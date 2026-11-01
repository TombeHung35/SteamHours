import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../harmony/entry/src/main/ets/components/StatusBarScrollStyle.ets', import.meta.url), 'utf8')
  .replace(/^import[^\n]*\n/gm, '').replace(/\bexport /g, '');
const code = stripTypeScriptTypes(source) + '\n;({ StatusBarScrollStyle })';
function modifier(deviceInfo) {
  const { StatusBarScrollStyle } = runInNewContext(code, { deviceInfo });
  return new StatusBarScrollStyle();
}

test('API 12-14 never access the new status-bar scroll API', () => {
  const unavailable = new Proxy({}, { get() { throw new Error('Unsupported API accessed'); } });
  for (const sdkApiVersion of [12, 13, 14]) modifier({ sdkApiVersion }).applyNormalAttribute(unavailable);
});

test('API 15 and current SDK enable native Scroll.backToTop without custom status-bar listeners', () => {
  for (const sdkApiVersion of [15, 18, 26]) {
    const calls = []; modifier({ sdkApiVersion }).applyNormalAttribute({ backToTop: enabled => calls.push(enabled) });
    assert.deepEqual(calls, [true]);
  }
});

test('Missing platform support or capability lookup failure leaves the scroll page usable', () => {
  assert.doesNotThrow(() => modifier({ sdkApiVersion: 26 }).applyNormalAttribute({}));
  assert.doesNotThrow(() => modifier({ sdkApiVersion: 26 }).applyNormalAttribute({ backToTop() { throw new Error('Unsupported system'); } }));
  assert.doesNotThrow(() => modifier(new Proxy({}, { get() { throw new Error('Unavailable capability'); } })).applyNormalAttribute({}));
});
