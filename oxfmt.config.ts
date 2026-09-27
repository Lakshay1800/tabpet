import { defineConfig } from 'oxfmt';
import ultracite from 'ultracite/oxfmt';

export default defineConfig({
  ...ultracite,
  // conformance/ is generated and never hand-edited; matching the formatter
  // would make the generator fragile against future oxfmt/ultracite changes
  ignorePatterns: [
    ...(ultracite.ignorePatterns ?? []),
    'apps/example/ios',
    'apps/example/android',
    'conformance',
  ],
  singleQuote: true,
  printWidth: 100,
});
