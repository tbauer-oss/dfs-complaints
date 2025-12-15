import test from 'node:test';
import assert from 'node:assert/strict';
import {
  AUDIT_FINDING_SEVERITY,
  auditActionSave,
  auditFindingSave,
  auditGet,
  auditSave,
  auditorSave,
  isAuditorQualified,
} from '../_lib/store.js';

function isoDaysFromNow(days) {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString();
}

function buildQualifiedAuditor(name = 'Test Auditor') {
  return {
    name,
    email: `${name.replace(/\s+/g, '.').toLowerCase()}@example.com`,
    qualifications: {
      internalAuditorTrainingDate: isoDaysFromNow(-600),
      experienceYears: 4,
      requalificationDueDate: isoDaysFromNow(100),
    },
  };
}

test('blocks auditor assignment when independence rules conflict', async () => {
  const auditor = await auditorSave({
    ...buildQualifiedAuditor('Conflict Auditor'),
    independenceRules: { restrictedOrgUnits: ['Operations'] },
  });
  await assert.rejects(
    () =>
      auditSave({
        title: 'Konflikt-Audit',
        auditeesOrgUnits: ['Operations'],
        plannedStart: isoDaysFromNow(1),
        plannedEnd: isoDaysFromNow(2),
        scopeText: 'Test Scope',
        leadAuditorId: auditor.id,
      }),
    /Konflikt/,
  );
});

test('detects overdue re-qualification', async () => {
  const auditor = await auditorSave({
    ...buildQualifiedAuditor('Expired Auditor'),
    qualifications: {
      internalAuditorTrainingDate: isoDaysFromNow(-1200),
      experienceYears: 4,
      requalificationDueDate: isoDaysFromNow(-1),
    },
  });
  assert.equal(isAuditorQualified(auditor), false);
});

test('computes default due dates based on finding severity', async () => {
  const auditor = await auditorSave(buildQualifiedAuditor('DueDate Auditor'));
  const audit = await auditSave({
    title: 'Frist-Test',
    plannedStart: isoDaysFromNow(1),
    plannedEnd: isoDaysFromNow(2),
    scopeText: 'Scope',
    leadAuditorId: auditor.id,
  });
  const finding = await auditFindingSave({
    auditId: audit.id,
    type: AUDIT_FINDING_SEVERITY.MAJOR,
    description: 'Schwerwiegende Abweichung',
  });
  const action = await auditActionSave({ auditId: audit.id, findingId: finding.id, description: 'Frist prüfen' });
  const due = new Date(action.dueDate).getTime();
  const anchor = new Date(audit.plannedEnd).getTime();
  const diffDays = Math.round((due - anchor) / (1000 * 60 * 60 * 24));
  assert.equal(diffDays, 90);
});

test('nachaudit triggered for ineffective actions', async () => {
  const auditor = await auditorSave(buildQualifiedAuditor('Nachaudit Auditor'));
  const audit = await auditSave({
    title: 'Nachaudit-Trigger',
    plannedStart: isoDaysFromNow(-2),
    plannedEnd: isoDaysFromNow(-1),
    scopeText: 'Scope',
    leadAuditorId: auditor.id,
  });
  const finding = await auditFindingSave({
    auditId: audit.id,
    type: AUDIT_FINDING_SEVERITY.MINOR,
    description: 'Kleinigkeit',
  });
  await auditActionSave({
    auditId: audit.id,
    findingId: finding.id,
    status: 'ineffective',
    description: 'Wirksamkeit fehlgeschlagen',
  });
  const updated = await auditGet(audit.id);
  assert.equal(updated.status, 'nachauditRequired');
});
