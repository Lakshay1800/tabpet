import RACCOON_IDLE_SPRITE from '../../assets/raccoon-idle-sprite.png';
import RACCOON_RUN_SPRITE from '../../assets/raccoon-run-sprite.png';
import RACCOON_SIT_SPRITE from '../../assets/raccoon-sit-sprite.png';
import type { CompanionProfile } from '../registry';
import { RUN_HEAD_PAD } from '../sheet-metrics';

export const raccoon: CompanionProfile = {
  id: 'raccoon',
  label: 'raccoon',
  sheets: { idle: RACCOON_IDLE_SPRITE, run: RACCOON_RUN_SPRITE, sit: RACCOON_SIT_SPRITE },
  runFps: 24,
  commitSpring: { duration: 430, dampingRatio: 0.82 },
  trackSpring: { duration: 240, dampingRatio: 0.86 },
  catchSpring: { duration: 260, dampingRatio: 0.9 },
  hopHeight: -8,
  flightLift: 0,
  scale: 0.72, // intentionally small: a scurrying raccoon reads better than reference size
  aroundRoute: true,
  headPad: RUN_HEAD_PAD.raccoon,
};
