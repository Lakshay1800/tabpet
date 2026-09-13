import SQUIRREL_IDLE_SPRITE from '../../assets/squirrel-idle-sprite.png';
import SQUIRREL_RUN_SPRITE from '../../assets/squirrel-run-sprite.png';
import SQUIRREL_SIT_SPRITE from '../../assets/squirrel-sit-sprite.png';
import type { CompanionProfile } from '../registry';
import { RUN_HEAD_PAD } from '../sheet-metrics';

export const squirrel: CompanionProfile = {
  id: 'squirrel',
  label: 'squirrel',
  sheets: { idle: SQUIRREL_IDLE_SPRITE, run: SQUIRREL_RUN_SPRITE, sit: SQUIRREL_SIT_SPRITE },
  runFps: 24,
  commitSpring: { duration: 400, dampingRatio: 0.78 },
  trackSpring: { duration: 220, dampingRatio: 0.82 },
  catchSpring: { duration: 240, dampingRatio: 0.9 },
  hopHeight: -14,
  flightLift: 0,
  scale: 0.85,
  headPad: RUN_HEAD_PAD.squirrel,
  // quickest of the set: scurries under the pill on far taps like the raccoon
  aroundRoute: true,
};
