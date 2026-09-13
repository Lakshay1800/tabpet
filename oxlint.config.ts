import { defineConfig } from 'oxlint';
import core from 'ultracite/oxlint/core';
import react from 'ultracite/oxlint/react';

export default defineConfig({
  extends: [core, react],
  ignorePatterns: [...(core.ignorePatterns ?? []), 'apps/example/ios', 'apps/example/android'],
  rules: {
    // RN idiom: component at the top, StyleSheet.create at the bottom
    'no-use-before-define': 'off',
    // style objects and fixtures are grouped by meaning, not alphabet
    'sort-keys': 'off',
    'func-style': 'off',
    'no-inline-comments': 'off',
    'require-await': 'off',
    // Hermes ES2023 array methods unverified on device; keep .sort()/.reverse()
    'unicorn/no-array-sort': 'off',
    'unicorn/no-array-reverse': 'off',
    'unicorn/prefer-structured-clone': 'off',
  },
  overrides: [
    {
      files: ['**/*.test.ts'],
      rules: {
        'typescript/no-non-null-assertion': 'off',
        'max-classes-per-file': 'off',
      },
    },
  ],
});
