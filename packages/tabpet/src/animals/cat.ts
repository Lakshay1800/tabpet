import CAT_IDLE_SPRITE from '../../assets/cat-idle-sprite.png';
import CAT_RUN_SPRITE from '../../assets/cat-run-sprite.png';
import CAT_SIT_SPRITE from '../../assets/cat-sit-sprite.png';
import type { CompanionProfile } from '../registry';
import { RUN_HEAD_PAD } from '../sheet-metrics';

export const cat: CompanionProfile = {
  id: 'cat',
  label: 'cat',
  sheets: { idle: CAT_IDLE_SPRITE, run: CAT_RUN_SPRITE, sit: CAT_SIT_SPRITE },
  runFps: 24,
  // a touch quicker off the mark than the reference animal
  commitSpring: { duration: 380, dampingRatio: 0.8 },
  trackSpring: { duration: 240, dampingRatio: 0.86 },
  catchSpring: { duration: 260, dampingRatio: 0.9 },
  hopHeight: -8,
  flightLift: 0,
  scale: 1,
  aroundRoute: false,
  headPad: RUN_HEAD_PAD.cat,
  // no ground shadow in the sit art: paws nearly reach the cell bottom
  footPad: 6.5,
};
