import test from 'node:test';
import assert from 'node:assert/strict';
import { gsprTdOptions } from '../api/_lib/gsprTdOptions.js';

test('GSPR TD options are sourced from static td_catalog file', async () => {
  const options = await gsprTdOptions();
  const keys = options.map((row) => row.key);
  assert.deepEqual(keys, ['MDR-TD1', 'MDR-TD2', 'MDR-TD3', 'MDR-TD4', 'MDR-TD5']);
  for (const row of options) {
    assert.match(row.label, /^MDR-TD\d+\s+–\s+.+$/);
  }
});
