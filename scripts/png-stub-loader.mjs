/**
 * Node module hook used only by gen-conformance.mjs: the animal profile
 * modules import their PNG sheets, which Node cannot load as ESM on its
 * own (no pixel data is read here, or needed - animals.json never encodes
 * `sheets`). Any other specifier passes through to the next loader (tsx's
 * TypeScript transform) unchanged.
 */
import { registerHooks } from 'node:module';

registerHooks({
  load(url, context, nextLoad) {
    if (url.endsWith('.png')) {
      return { format: 'module', shortCircuit: true, source: 'export default { uri: "stub" };' };
    }
    return nextLoad(url, context);
  },
});
