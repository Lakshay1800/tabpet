/**
 * All six built-in profiles in one module - importing this (or `tabpet`,
 * which imports it for you) bundles every sprite sheet. A host that wants
 * to ship fewer animals should import `tabpet/bare` plus only the
 * `tabpet/animals/<id>` modules it needs instead.
 */
import { registerCompanion } from '../registry';
import { bird } from './bird';
import { cat } from './cat';
import { panda } from './panda';
import { raccoon } from './raccoon';
import { squirrel } from './squirrel';
import { turtle } from './turtle';

export { bird } from './bird';
export { cat } from './cat';
export { panda } from './panda';
export { raccoon } from './raccoon';
export { squirrel } from './squirrel';
export { turtle } from './turtle';

/** Idempotent: safe to call more than once, each call just overwrites with
 *  the same six profiles. */
export function registerBuiltinCompanions(): void {
  registerCompanion(panda);
  registerCompanion(cat);
  registerCompanion(turtle);
  registerCompanion(raccoon);
  registerCompanion(bird);
  registerCompanion(squirrel);
}
