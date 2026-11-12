// Pure build planner.  No network, uploads or release state changes.
// One shared merge-timestamp build per app across iOS and macOS (owner, Oct 29 2026).
// build = max(S, M + 1), a plain integer, where
//   S = the committer date of the merge commit in America/Chicago as
//       YYYYMMDDHHMM (12 digits, ^[1-9][0-9]{11}$), and
//   M = the highest first numeric component among EVERY build of the app on
//       iOS and of its paired macOS app (all trains, expired included, old
//       timestamp-style builds included) plus every extra floor.
// A rebuild of the same commit still goes up, because S is already taken and
// the next plan lands on M + 1.  There is no floor and no cap:  the value
// grows past any inventory.
export function nextSharedBuild({iosBuilds, macBuilds, extraFloors = [], complete, mergeStamp}) {
  if (complete !== true || !Array.isArray(iosBuilds) || !Array.isArray(macBuilds)) {
    throw new Error('complete build inventory required');
  }
  if (typeof mergeStamp !== 'string' || !/^[1-9][0-9]{11}$/.test(mergeStamp)) {
    throw new Error('merge stamp must be ^[1-9][0-9]{11}$');
  }
  if (!Array.isArray(extraFloors)) throw new Error('malformed build inventory');
  for (const floor of extraFloors) {
    if (typeof floor !== 'number' || !Number.isSafeInteger(floor) || floor < 0) {
      throw new Error('malformed build inventory');
    }
  }
  // Validate everything before computing; malformed evidence is never ignored.
  const re = /^[0-9]+(\.[0-9]+){0,2}$/;
  for (const value of [...iosBuilds, ...macBuilds]) {
    if (typeof value !== 'string' || !re.test(value)) throw new Error('malformed build inventory');
  }
  const stamp = BigInt(mergeStamp);
  let max = -1n;
  for (const value of [...iosBuilds, ...macBuilds]) {
    const first = BigInt(value.split('.')[0]);
    if (first > max) max = first;
  }
  for (const floor of extraFloors) {
    const candidate = BigInt(floor);
    if (candidate > max) max = candidate;
  }
  const next = max + 1n > stamp ? max + 1n : stamp;
  return {build: String(next)};
}
