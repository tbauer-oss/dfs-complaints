import test from 'node:test';
import assert from 'node:assert/strict';
import { tdCreate, tdComputedSummary, tdLinkCreate, tdSections } from '../api/_lib/tdStore.js';

test('TD readiness detects missing mandatory links', async () => {
  const td = await tdCreate({ code: 'MDR-TD-UT-1', title: 'Unit TD' }, 'tester');
  const summary = await tdComputedSummary(td);
  assert.equal(summary.readinessStatus, 'Yellow');
  assert.ok(summary.reasons.some((r) => r.includes('Missing mandatory link: GSPR')));
});

test('TD readiness score improves with key links', async () => {
  const td = await tdCreate({ code: 'MDR-TD-UT-2', title: 'Unit TD 2' }, 'tester');
  const sections = await tdSections(td.id);
  const pmsSection = sections.find((s) => s.templateKey === 'ANNEX_III_G');
  await tdLinkCreate(td.id, { type: 'FMEA', label: 'Risk File', refId: 'FMEA-1' });
  await tdLinkCreate(td.id, { type: 'GSPR', label: 'GSPR matrix', refId: 'GSPR-1' });
  await tdLinkCreate(td.id, { type: 'Report', label: 'Clinical Evaluation', refId: 'CER-1' });
  await tdLinkCreate(td.id, { type: 'Document', sectionId: pmsSection?.id, label: 'PMS plan', refId: 'PMS-1' });
  const summary = await tdComputedSummary(td);
  assert.ok(summary.complianceScore >= 30);
});
