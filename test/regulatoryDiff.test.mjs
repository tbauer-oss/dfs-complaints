import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeText } from '../api/_lib/regulatory/normalize.js';
import { sha256 } from '../api/_lib/regulatory/hash.js';
import { computeSectionDiff } from '../api/_lib/regulatory/diff.js';

test('normalizeText collapses whitespace', () => {
  assert.equal(normalizeText(' A\r\n\r\nB\u00a0\tC '), 'A\n\nB C');
});

test('sha256 stable hash', () => {
  assert.equal(sha256('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
});

test('computeSectionDiff returns added/removed/modified counts', () => {
  const oldSections = [
    { section_key: 'Art_1', section_type: 'article', content_hash: 'a' },
    { section_key: 'Art_2', section_type: 'article', content_hash: 'b' },
  ];
  const newSections = [
    { section_key: 'Art_1', section_type: 'article', content_hash: 'z' },
    { section_key: 'Art_3', section_type: 'article', content_hash: 'c' },
  ];
  const diff = computeSectionDiff(oldSections, newSections);
  assert.deepEqual(diff.counts, { added: 1, removed: 1, modified: 1 });
});
