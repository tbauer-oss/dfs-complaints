import test from 'node:test';
import assert from 'node:assert/strict';
import { buildMdrRuleReference, legalReferenceResolver } from '../api/_lib/legalRefService.js';

test('TD legal rule reference points to cached regulatory section', () => {
  const ref = buildMdrRuleReference(11);
  assert.ok(ref);
  assert.equal(ref.legal_document_slug, 'mdr-2017-745');
  assert.equal(ref.section_key, 'Annex_VIII_Rule_11');
  assert.equal(ref.metaJson?.documentSlug, 'mdr-2017-745');
});

test('legal resolver returns section_key for TD usage', () => {
  const item = legalReferenceResolver('MDR_CLASSIFICATION_RULE', '11');
  assert.ok(item);
  assert.equal(item.document_slug, 'mdr-2017-745');
  assert.equal(item.section_key, 'Annex_VIII_Rule_11');
});
