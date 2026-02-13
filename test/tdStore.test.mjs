import test from 'node:test';
import assert from 'node:assert/strict';
import { tdCreate, tdComputedSummary, tdLinkCreate, tdSections, tdList } from '../api/_lib/tdStore.js';

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
import { tdApplicabilityGet, tdApplicabilityProfileUpsert, generateApplicability, tdBootstrapQueries, tdQueries } from '../api/_lib/tdStore.js';

test('TD applicability defaults: software V&V is N/A when hasSoftware=false', async () => {
  const td = await tdCreate({ code: 'MDR-TD-UT-3', title: 'Unit TD 3' }, 'tester');
  await tdBootstrapQueries(td.id);
  const app = await tdApplicabilityGet(td.id);
  const sw = app.results.find((r) => r.queryKey === 'ANNEX_II_F_6');
  assert.equal(sw?.state, 'NOT_APPLICABLE');
});

test('TD applicability: reprocessing mandatory only when reusable=true', async () => {
  const td = await tdCreate({ code: 'MDR-TD-UT-4', title: 'Unit TD 4' }, 'tester');
  await tdApplicabilityProfileUpsert(td.id, { profileType: 'DENTAL_ALLOYS', isReusable: false, isSterile: false, packagingType: 'UNIT_NONSTERILE', hasSoftware: false }, null);
  await generateApplicability(td.id);
  const app = await tdApplicabilityGet(td.id);
  const repro = app.results.find((r) => r.queryKey === 'ANNEX_II_F_3');
  assert.equal(repro?.state, 'NOT_APPLICABLE');
});

test('TD query payload includes applicability flags', async () => {
  const td = await tdCreate({ code: 'MDR-TD-UT-5', title: 'Unit TD 5' }, 'tester');
  await tdApplicabilityProfileUpsert(td.id, { profileType: 'DENTAL_ALLOYS', isReusable: false, isSterile: false, packagingType: 'UNIT_NONSTERILE', hasSoftware: false }, null);
  await generateApplicability(td.id);
  const queries = await tdQueries(td.id);
  const software = queries.find((q) => q.templateKey === 'ANNEX_II_F_6');
  assert.equal(software?.applicability?.state, 'NOT_APPLICABLE');
});

test('TD list hides auto-generated template test entries', async () => {
  await tdCreate({ code: `MDR-TD-AUTO-${Date.now()}`, title: 'Template Test' }, 'tester');
  const list = await tdList();
  assert.equal(list.some((entry) => String(entry.code).startsWith('MDR-TD-AUTO-')), false);
});
