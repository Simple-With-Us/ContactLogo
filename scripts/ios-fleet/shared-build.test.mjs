import test from 'node:test';
import assert from 'node:assert/strict';
import {nextSharedBuild as next} from './shared-build.mjs';
const STAMP = '202610290000';
const input = {iosBuilds: [], macBuilds: [], complete: true, mergeStamp: STAMP};
test('fresh app ships the merge stamp', () => {
  assert.deepEqual(next(input), {build: STAMP});
});
test('existing builds below the stamp lose to it', () => {
  assert.deepEqual(next({...input, iosBuilds: ['1200']}), {build: STAMP});
  assert.deepEqual(next({...input, macBuilds: ['1300']}), {build: STAMP});
  assert.deepEqual(next({...input, iosBuilds: ['1200'], macBuilds: ['1300']}), {build: STAMP});
  assert.deepEqual(next({...input, extraFloors: [1400]}), {build: STAMP});
  assert.deepEqual(next({...input, iosBuilds: ['0.1.3', '1.1.2']}), {build: STAMP});
});
test('an existing build at or above the stamp moves one up', () => {
  assert.deepEqual(next({...input, iosBuilds: [STAMP]}), {build: '202610290001'});
  assert.deepEqual(next({...input, iosBuilds: ['209912312359']}), {build: '209912312360'});
  assert.deepEqual(next({...input, macBuilds: ['209912312359']}), {build: '209912312360'});
  // Dotted values count by their first numeric component.
  assert.deepEqual(next({...input, iosBuilds: ['209912312359.2']}), {build: '209912312360'});
});
test('iOS timestamp builds count (they are no longer ignored)', () => {
  assert.deepEqual(
    next({...input, iosBuilds: ['202610190645'], mergeStamp: '202610180000'}),
    {build: '202610190646'}
  );
  assert.deepEqual(
    next({...input, iosBuilds: ['202610190645', '1200'], mergeStamp: '202610180000'}),
    {build: '202610190646'}
  );
});
test('mac-only higher build wins', () => {
  assert.deepEqual(
    next({...input, iosBuilds: ['1200'], macBuilds: ['209912312359']}),
    {build: '209912312360'}
  );
});
test('paired apps concatenate: max across both apps plus a floor (owner rule)', () => {
  // plan-release-build passes IOS(app)+IOS(paired) as iosBuilds and
  // MAC_OS(app)+MAC_OS(paired) as macBuilds; the planner takes the max.
  assert.deepEqual(
    next({iosBuilds: ['1200', '1500'], macBuilds: ['1100', '1300'], extraFloors: [1400], complete: true, mergeStamp: STAMP}),
    {build: STAMP}
  );
  assert.deepEqual(
    next({iosBuilds: ['1200', '1500'], macBuilds: ['1100', '209912312359'], extraFloors: [1400], complete: true, mergeStamp: STAMP}),
    {build: '209912312360'}
  );
});
test('extra floors join the max', () => {
  assert.deepEqual(next({...input, extraFloors: [209912312359]}), {build: '209912312360'});
  assert.deepEqual(
    next({...input, iosBuilds: ['1200'], extraFloors: [209912312359]}),
    {build: '209912312360'}
  );
});
test('bad mergeStamp throws before computing', () => {
  for (const bad of [undefined, null, 202610290000, '', '20261029000', '2026102900000', '022610290000', '2026-10-29', ' 202610290000', 'v1']) {
    assert.throws(() => next({...input, mergeStamp: bad}), /merge stamp must be/);
  }
});
test('malformed inventory throws before computing', () => {
  for (const bad of [null, 'NaN', '1.2.3.4', 42, '', ' 1000', 'v1']) {
    assert.throws(() => next({...input, iosBuilds: [bad]}), /malformed build inventory/);
    assert.throws(() => next({...input, macBuilds: [bad]}), /malformed build inventory/);
  }
  for (const bad of [-1, 1.5, NaN, '1500', null]) {
    assert.throws(() => next({...input, extraFloors: [bad]}), /malformed build inventory/);
  }
  // A malformed entry is reported even when a range error would also apply.
  assert.throws(() => next({...input, iosBuilds: ['209912312359', 'NaN']}), /malformed build inventory/);
});
test('incomplete inventory refuses', () => {
  assert.throws(() => next({...input, complete: false}), /complete build inventory required/);
  assert.throws(() => next({...input, complete: undefined}), /complete build inventory required/);
  assert.throws(() => next({iosBuilds: [], complete: true, mergeStamp: STAMP}), /complete build inventory required/);
  assert.throws(() => next({macBuilds: [], complete: true, mergeStamp: STAMP}), /complete build inventory required/);
  assert.throws(() => next({iosBuilds: '1200', macBuilds: [], complete: true, mergeStamp: STAMP}), /complete build inventory required/);
});
