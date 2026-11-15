// Bundle budget: the JavaScript and CSS the browser downloads for the first page, gzipped. Raise the budget in a
// reviewed change, with the reason; don't raise it to get green.
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';

const budgetKb = 150;
const dir = 'dist/assets';
const files = readdirSync(dir).filter((name) => /\.(js|css)$/.test(name));
const bytes = files.reduce((sum, name) => sum + gzipSync(readFileSync(join(dir, name))).length, 0);
const kb = bytes / 1024;
console.log(`bundle: ${kb.toFixed(1)} kB gzipped in ${String(files.length)} files (budget ${String(budgetKb)} kB)`);
if (files.length === 0 || kb > budgetKb) {
  console.error(files.length === 0 ? 'bundle: nothing was built' : 'bundle: over budget');
  process.exit(1);
}
