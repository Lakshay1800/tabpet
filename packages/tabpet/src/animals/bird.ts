import BIRD_IDLE_SPRITE from '../../assets/bird-idle-sprite.png';
import BIRD_RUN_SPRITE from '../../assets/bird-run-sprite.png';
import BIRD_SIT_SPRITE from '../../assets/bird-sit-sprite.png';
import type { CompanionProfile } from '../registry';
import { RUN_HEAD_PAD } from '../sheet-metrics';

export const bird: CompanionProfile = {
  id: 'bird',
  label: 'bird',
  sheets: { idle: BIRD_IDLE_SPRITE, run: BIRD_RUN_SPRITE, sit: BIRD_SIT_SPRITE },
  runFps: 24,
  // bird flies: lifts off the bar line while running, perches normally otherwise
  commitSpring: { duration: 380, dampingRatio: 0.75 },
  trackSpring: { duration: 220, dampingRatio: 0.8 },
  catchSpring: { duration: 260, dampingRatio: 0.9 },
  hopHeight: 0,
  flightLift: 14,
  scale: 1,
  aroundRoute: false,
  headPad: RUN_HEAD_PAD.bird,
  // no ground shadow: the drawn legs reach close to the cell bottom
  footPad: 7.5,
};
