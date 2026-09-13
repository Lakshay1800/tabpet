import { defineConfig } from 'oxfmt';
import ultracite from 'ultracite/oxfmt';

export default defineConfig({
  ...ultracite,
  ignorePatterns: [...(ultracite.ignorePatterns ?? []), 'apps/example/ios', 'apps/example/android'],
  singleQuote: true,
  printWidth: 100,
});
