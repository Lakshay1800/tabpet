#!/usr/bin/env node
// Discovers every *.test.ts under packages/ and runs each under tsx sequentially.
// Refuses to pass vacuously. Node runtime; Bun is the package manager only.
import { execFileSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const packagesDir = path.join(root, 'packages');

function discover(dir) {
  const found = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === 'node_modules' || entry.name === 'build') {
        continue;
      }
      found.push(...discover(full));
    } else if (entry.name.endsWith('.test.ts')) {
      found.push(full);
    }
  }
  return found;
}

const files = discover(packagesDir).sort();
if (files.length === 0) {
  console.error('run-tests: no test files discovered');
  process.exit(1);
}
console.log(`run-tests: ${files.length} suites`);
for (const file of files) {
  try {
    execFileSync('bunx', ['tsx', file], { stdio: 'inherit', cwd: root });
  } catch {
    console.error(`run-tests: FAILED ${path.relative(root, file)}`);
    process.exit(1);
  }
}
console.log(`run-tests: all ${files.length} suites passed`);
