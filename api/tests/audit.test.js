import test from 'node:test';
import assert from 'node:assert/strict';
import {
  AUDIT_FINDING_SEVERITY,
  auditActionSave,
  auditFindingSave,
  auditGet,
  auditSave,
  auditorSave,
  auditorAll,
  __setRedisClientForTests,
  isAuditorQualified,
  auditUpdate,
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

function createMockRes() {
  const headers = new Map();
  let body = '';
  return {
    statusCode: 200,
    setHeader: (k, v) => headers.set(k, v),
    getHeader: (k) => headers.get(k),
    end: (chunk) => {
      body = chunk?.toString?.() || '';
    },
    _getBody: () => body,
    _headers: headers,
  };
}

async function invokeAuditHandler(handler, { method = 'POST', body = {}, headers = {}, query = {} } = {}) {
  const res = createMockRes();
  const req = {
    method,
    headers: { 'content-type': 'application/json', ...headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
    query,
  };
  await handler(req, res);
  const raw = res._getBody();
  const parsed = raw ? JSON.parse(raw) : {};
  return { res, parsed };
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

test('maps auditor objects and still blocks unknown auditors without upserting', async () => {
  const beforeCount = (await auditorAll()).length;
  const lead = await auditorSave(buildQualifiedAuditor('Primary Lead'));
  const audit = await auditSave({
    title: 'Valid Audit',
    plannedStart: isoDaysFromNow(1),
    plannedEnd: isoDaysFromNow(2),
    scopeText: 'Scope',
    orgUnit: 'Operations',
    leadAuditorId: lead.id,
  });

  const updated = await auditUpdate(audit.id, { leadAuditor: { id: lead.id, name: 'Alias Lead' } });
  assert.equal(updated.leadAuditorId, lead.id);

  const withCo = await auditUpdate(audit.id, { coAuditors: [{ id: lead.id }] });
  assert.deepEqual(withCo.coAuditorIds, [lead.id]);

  await assert.rejects(() => auditUpdate(audit.id, { leadAuditorId: 'does-not-exist' }), /nicht gefunden/);
  await assert.rejects(() => auditUpdate(audit.id, { coAuditorIds: ['unknown-co'] }), /nicht gefunden/);

  const auditorsAfter = await auditorAll();
  assert.ok(auditorsAfter.find(a => a.id === lead.id));
  assert.equal(auditorsAfter.length, beforeCount + 1);
});

test('enforces independence between auditor org unit and audit org unit', async () => {
  const lead = await auditorSave({
    ...buildQualifiedAuditor('Independence Lead'),
    orgUnit: 'QA',
  });
  await assert.rejects(
    () =>
      auditSave({
        title: 'OrgUnit Conflict',
        plannedStart: isoDaysFromNow(1),
        plannedEnd: isoDaysFromNow(2),
        scopeText: 'Scope',
        orgUnit: 'QA',
        leadAuditorId: lead.id,
      }),
    /eigenen Bereich/,
  );
});

test('POST handler accepts leadAuditorId and returns validation details for errors', async () => {
  process.env.ADMIN_SECRET = 'test-secret';
  const { default: handler } = await import('../admin/audits.js');
  const lead = await auditorSave(buildQualifiedAuditor('Handler Lead'));

  const validPayload = {
    title: 'Handler Audit',
    plannedStart: isoDaysFromNow(1),
    plannedEnd: isoDaysFromNow(2),
    scopeText: 'Scope',
    leadAuditorId: lead.id,
  };
  const { res: okRes, parsed: okParsed } = await invokeAuditHandler(handler, {
    method: 'POST',
    body: validPayload,
    headers: { 'x-admin-secret': 'test-secret' },
  });
  assert.equal(okRes.statusCode, 200);
  assert.equal(okParsed.ok, true);
  assert.equal(okParsed.audit.leadAuditorId, lead.id);

  const invalidPayload = { ...validPayload, title: 'Bad Lead', leadAuditorId: 'unknown-lead' };
  const { res: badRes, parsed: badParsed } = await invokeAuditHandler(handler, {
    method: 'POST',
    body: invalidPayload,
    headers: { 'x-admin-secret': 'test-secret' },
  });
  assert.equal(badRes.statusCode, 400);
  assert.ok(/Lead Auditor/.test(badParsed.error));
  assert.ok(Array.isArray(badParsed.details));
  assert.ok(badParsed.details.some(d => JSON.stringify(d).includes('leadAuditorId')));
});

test('persists auditors to redis when a redis client is available', async () => {
  const calls = [];
  const fakeRedis = {
    async set(key, value) {
      calls.push({ op: 'set', key, value });
      return 'ok';
    },
    async get() { return null; },
    async del() { return null; },
  };
  __setRedisClientForTests(fakeRedis);
  const auditor = await auditorSave(buildQualifiedAuditor('Redis Auditor'), { persist: true });
  __setRedisClientForTests(null);

  assert.ok(
    calls.some(c => c.op === 'set' && typeof c.key === 'string' && c.key.includes(auditor.id)),
    'redis set should include auditor key',
  );
});
