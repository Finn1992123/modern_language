import test from 'node:test';
import assert from 'node:assert/strict';
import { nextVersionCode, releaseBody } from './play-console.mjs';

test('version code includes local, all tracks, and uploaded artifacts', () => {
  assert.equal(nextVersionCode(4, [{ releases: [{ versionCodes: ['12'] }] }], [{ versionCode: 15 }], [{ versionCode: 18 }]), 19);
  assert.equal(nextVersionCode(20, []), 21);
  assert.throws(() => nextVersionCode(2100000000, []));
  assert.throws(() => nextVersionCode(4, [{ releases: [{ versionCodes: ['bad'] }] }]));
});

test('does not overwrite drafts or active staged rollouts', () => {
  for (const status of ['draft', 'inProgress', 'halted']) {
    assert.throws(() => releaseBody('production', { releases: [{ status }] }, 5, 'Update'));
  }
});

test('requires supported track and actual release notes', () => {
  assert.throws(() => releaseBody('unknown', {}, 5, 'Update'));
  assert.throws(() => releaseBody('internal', {}, 5, ' '));
  assert.throws(() => releaseBody('internal', {}, 5, 'x'.repeat(501)));
  assert.deepEqual(releaseBody('production', { releases: [{ status: 'completed' }] }, 5, ' Ενημέρωση '), {
    track: 'production', releases: [{ status: 'completed', versionCodes: ['5'], releaseNotes: [{ language: 'el-GR', text: 'Ενημέρωση' }] }]
  });
});
