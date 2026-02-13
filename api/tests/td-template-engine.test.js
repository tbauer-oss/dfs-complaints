import test from 'node:test';
import assert from 'node:assert/strict';
import { tdCreate, tdSections, tdBootstrapQueries, tdQueries, tdQueryUpdate, tdNodeTemplates } from '../_lib/tdStore.js';
import { resolveMdrClassificationRule } from '../_lib/legalRefService.js';

test('td template engine exposes dedicated templates for Struktur nodes', async () => {
  const templates = tdNodeTemplates('ANNEX_II_A');
  const classification = templates.find((t) => t.templateKey === 'ANNEX_II_A_4');
  assert.ok(classification);
  assert.equal(classification.nodeTemplate.templateType, 'CLASSIFICATION_RULE');
  assert.ok(classification.nodeTemplate.fields.some((f) => f.key === 'mdrClass'));
  assert.ok(classification.nodeTemplate.fields.some((f) => f.key === 'classificationRule'));
});

test('classification query auto-attaches MDR legal reference and becomes completable', async () => {
  const td = await tdCreate({ code: `MDR-TD-AUTO-${Date.now()}`, title: 'Template Test' }, 'tester@example.com');
  const sections = await tdSections(td.id);
  const sectionA = sections.find((s) => s.templateKey === 'ANNEX_II_A');
  assert.ok(sectionA);
  await tdBootstrapQueries(td.id);

  const classification = (await tdQueries(td.id, sectionA.id)).find((q) => q.templateKey === 'ANNEX_II_A_4');
  assert.ok(classification);

  await tdQueryUpdate(classification.id, {
    fieldResponses: { mdrClass: 'IIa', classificationRule: '11', justificationMd: 'Auto justification seed' },
  });

  const updated = (await tdQueries(td.id, sectionA.id)).find((q) => q.templateKey === 'ANNEX_II_A_4');
  assert.ok(updated.links.some((l) => String(l.refId || '').startsWith('MDR_RULE_')));
  assert.equal(updated.validation.canComplete, true);
});

test('legal resolver returns Annex VIII rule metadata', () => {
  const rule = resolveMdrClassificationRule(11);
  assert.ok(rule);
  assert.equal(rule.rule_no, 11);
  assert.match(rule.mdr_ref, /Anhang VIII/);
});
