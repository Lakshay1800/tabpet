import { strictEqual } from 'node:assert';

import { resolveCompanionId } from './companion-id';

const KNOWN = ['panda', 'cat', 'turtle', 'raccoon', 'bird', 'squirrel'];

function testValidIdPassesThrough() {
  for (const id of KNOWN) {
    strictEqual(resolveCompanionId(id, KNOWN, 'panda'), id, `${id} passes through unchanged`);
  }
}

function testUnknownStringFallsBackToFallback() {
  strictEqual(resolveCompanionId('wolf', KNOWN, 'panda'), 'panda', 'unrecognized id falls back');
  strictEqual(resolveCompanionId('', KNOWN, 'panda'), 'panda', 'empty string falls back');
}

function testNullishFallsBackToFallback() {
  strictEqual(resolveCompanionId(null, KNOWN, 'panda'), 'panda', 'null falls back');
  strictEqual(resolveCompanionId(undefined, KNOWN, 'panda'), 'panda', 'undefined falls back');
}

function main() {
  testValidIdPassesThrough();
  testUnknownStringFallsBackToFallback();
  testNullishFallsBackToFallback();
  console.log('companion-id: 3 tests passed');
}

void main();
