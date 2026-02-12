import test from 'node:test';
import assert from 'node:assert/strict';
import { getUniqueMdrTdEntries } from '../api/_lib/products.js';

test('MDR-TD catalog entries are unique and normalized', async () => {
  const items = await getUniqueMdrTdEntries();
  assert.ok(items.length > 0);
  const codes = items.map((item) => item.code);
  const uniqueCodes = new Set(codes);
  assert.equal(uniqueCodes.size, codes.length);
  for (const code of codes) {
    assert.match(code, /^MDR-TD\d+$/i);
  }
});
