import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../harmony/entry/src/main/ets/model/AccountNavigation.ets', import.meta.url), 'utf8').replaceAll('export ', '');
const { AccountNavigation } = runInNewContext(stripTypeScriptTypes(source) + '\n({ AccountNavigation })');
function flow() {
  const stack = []; const parameters = [];
  const paths = { getAllPathName: () => stack.slice(), size: () => stack.length,
    pushPathByName(name, param) { stack.push(name); parameters.push(param); },
    pop: () => stack.pop(), clear() { stack.length = 0; } };
  return { navigation: new AccountNavigation(paths), stack, parameters };
}

test('Family login cannot open before Navigation is mounted', () => {
  const f = flow(); f.navigation.openFamily(); assert.deepEqual(f.stack, []);
});

test('Family login pushes only its temporary page and cannot duplicate it', () => {
  const f = flow(); f.navigation.markReady(); f.navigation.openFamily(); f.navigation.openFamily();
  assert.deepEqual(f.stack, ['family']);
});

test('Closing login reveals the persistent root instead of an account back stack', () => {
  const f = flow(); f.navigation.markReady(); f.navigation.openFamily();
  assert.equal(f.navigation.back(), true); assert.deepEqual(f.stack, []);
  assert.equal(f.navigation.back(), false);
});

test('Returning to the library clears only temporary authorization history', () => {
  const f = flow(); f.navigation.markReady(); f.navigation.openFamily(); f.navigation.returnLibrary();
  assert.deepEqual(f.stack, []); f.navigation.markReady(); assert.deepEqual(f.stack, []);
});

test('Temporary family navigation never receives account credentials', () => {
  const f = flow(); f.navigation.markReady(); f.navigation.openFamily();
  assert.ok(f.parameters.every(param => param === undefined));
});
