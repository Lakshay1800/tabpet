import PANDA_IDLE_SPRITE from '../../assets/panda-idle-sprite.png';
import PANDA_RUN_SPRITE from '../../assets/panda-run-sprite.png';
import PANDA_SIT_SPRITE from '../../assets/panda-sit-sprite.png';
import type { CompanionProfile } from '../registry';
import { RUN_HEAD_PAD } from '../sheet-metrics';

export const panda: CompanionProfile = {
  id: 'panda',
  label: 'panda',
  sheets: { idle: PANDA_IDLE_SPRITE, run: PANDA_RUN_SPRITE, sit: PANDA_SIT_SPRITE },
  runFps: 18,
  // heavier, lumbering
  commitSpring: { duration: 560, dampingRatio: 0.86 },
  trackSpring: { duration: 300, dampingRatio: 0.9 },
  catchSpring: { duration: 260, dampingRatio: 0.9 },
  hopHeight: -6,
  flightLift: 0,
  scale: 1,
  aroundRoute: false,
  headPad: RUN_HEAD_PAD.panda,
  // measured: the front paw ends 16px above the cell bottom (240px cell).
  // Sheets are cut without a painted ground shadow (tools/deshadow.sh), so
  // the paw line is the contact and the panda sits on the rim.
  footPad: 3.6,
  seatLift: 2,
};
