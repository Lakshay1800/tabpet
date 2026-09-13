import TURTLE_IDLE_SPRITE from '../../assets/turtle-idle-sprite.png';
import TURTLE_RUN_SPRITE from '../../assets/turtle-run-sprite.png';
import TURTLE_SIT_SPRITE from '../../assets/turtle-sit-sprite.png';
import type { CompanionProfile } from '../registry';
import { RUN_HEAD_PAD } from '../sheet-metrics';

export const turtle: CompanionProfile = {
  id: 'turtle',
  label: 'turtle',
  sheets: { idle: TURTLE_IDLE_SPRITE, run: TURTLE_RUN_SPRITE, sit: TURTLE_SIT_SPRITE },
  runFps: 12,
  // a turtle can't run, so it slowly follows the bar and never hops
  runSpeed: 200,
  commitSpring: { duration: 1050, dampingRatio: 1 },
  trackSpring: { duration: 700, dampingRatio: 1 },
  catchSpring: { duration: 600, dampingRatio: 1 },
  hopHeight: 0,
  flightLift: 0,
  scale: 1,
  aroundRoute: false,
  headPad: RUN_HEAD_PAD.turtle,
  // no ground shadow: the shell's underside is the cell's near-bottom
  footPad: 6.5,
};
