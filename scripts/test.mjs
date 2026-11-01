import { readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = fileURLToPath(new URL('../', import.meta.url));
const full = process.argv.includes('--compiled');
const compiled = new URL('../harmony/entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/Index.ts', import.meta.url);
if (full && !existsSync(compiled)) {
  console.error('Run assembleHap in harmony/ before npm run test:full.');
  process.exit(1);
}
const tests = readdirSync(new URL('../tests/', import.meta.url))
  .filter(name => name.endsWith('.test.mjs') && (full || name !== 'compiled-account-ui.test.mjs'))
  .sort().map(name => 'tests/' + name);
const result = spawnSync(process.execPath, ['--test', ...tests], { cwd: root, stdio: 'inherit' });
if (result.error) console.error(result.error.message);
process.exit(result.status ?? 1);
