import { ok } from 'node:assert/strict';

import { shouldApplyArrive } from './perch-reentry';

function testArriveOnlyWhenGenerationMatches(): void {
  ok(
    shouldApplyArrive({ callbackGeneration: 3, currentGeneration: 3, mounted: true }),
    'matching generation on a live instance may sit'
  );
  ok(
    !shouldApplyArrive({ callbackGeneration: 3, currentGeneration: 4, mounted: true }),
    'stale generation after re-entry must not sit'
  );
  ok(
    !shouldApplyArrive({ callbackGeneration: 3, currentGeneration: 3, mounted: false }),
    'unmounted arrive is ignored even if the generation matches'
  );
}

testArriveOnlyWhenGenerationMatches();
