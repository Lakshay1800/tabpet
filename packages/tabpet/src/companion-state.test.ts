import {
  beginCompanionBusy,
  __resetCompanionStateForTest,
  isCompanionBusy,
  subscribeCompanionBusy,
} from './companion-state';

function assert(condition: boolean, message: string) {
  if (!condition) {
    throw new Error(message);
  }
}

function testBusyClaimsRefCountAndEdgeBroadcast() {
  __resetCompanionStateForTest();
  const seen: boolean[] = [];
  const unsubscribe = subscribeCompanionBusy((busy) => seen.push(busy));

  assert(!isCompanionBusy(), 'baseline: no claims, not busy');
  const release1 = beginCompanionBusy();
  const release2 = beginCompanionBusy();
  assert(isCompanionBusy(), 'busy while any claim is held');
  release1();
  assert(isCompanionBusy(), 'still busy with one claim outstanding');
  release2();
  assert(!isCompanionBusy(), 'idle again after the last release');
  release2(); // idempotent: a finally-block re-release must not underflow
  assert(!isCompanionBusy(), 'double release does not underflow the count');
  const release3 = beginCompanionBusy();
  assert(isCompanionBusy(), 'a fresh claim after a double release still works');
  release3();

  // only idle<->busy EDGES broadcast: the overlapping claim and first release are silent
  assert(
    seen.join(',') === 'true,false,true,false',
    `edge-only broadcasts expected true,false,true,false got ${seen.join(',')}`
  );

  unsubscribe();
  const release4 = beginCompanionBusy();
  release4();
  assert(seen.length === 4, 'unsubscribed listener observes nothing further');
  __resetCompanionStateForTest();
  assert(!isCompanionBusy(), 'test reset clears outstanding claims');
}

function testBusyClaimNoOpsWhenNothingSubscribed() {
  __resetCompanionStateForTest();
  const release = beginCompanionBusy();
  assert(isCompanionBusy(), 'busy state tracks with zero subscribers');
  release();
  assert(!isCompanionBusy(), 'release works with zero subscribers');
  __resetCompanionStateForTest();
}

function main() {
  testBusyClaimsRefCountAndEdgeBroadcast();
  testBusyClaimNoOpsWhenNothingSubscribed();
  console.log('companion-state: all tests passed');
}

main();
