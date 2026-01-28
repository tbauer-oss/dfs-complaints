import test from 'node:test';
import assert from 'node:assert/strict';
import {
  __setRedisClientForTests,
  nextTrainingNumber,
  trainingRecordSave,
  trainingQuestionnairesAll,
} from '../_lib/store.js';

function fakeRedis() {
  const counters = new Map();
  return {
    async incr(key) {
      const val = (counters.get(key) || 0) + 1;
      counters.set(key, val);
      return val;
    },
    async set() { return 'ok'; },
    async get() { return null; },
    async del() { return null; },
    async keys() { return []; },
  };
}

test('generates unique training numbers per year', async () => {
  __setRedisClientForTests(fakeRedis());
  const first = await nextTrainingNumber({ year: 2026 });
  const second = await nextTrainingNumber({ year: 2026 });
  const otherYear = await nextTrainingNumber({ year: 2027 });
  assert.notEqual(first, second);
  assert.match(first, /TRN-2026-0001/);
  assert.match(second, /TRN-2026-0002/);
  assert.match(otherYear, /TRN-2027-0001/);
});

test('assigns questionnaires when participants attend', async () => {
  __setRedisClientForTests(fakeRedis());
  const training = await trainingRecordSave({
    title: 'Test Training',
    defaultQuestionnaireTemplateId: 'template-1',
    participants: [
      { name: 'Anna Beispiel', status: 'attended', email: 'anna@example.com' },
      { name: 'Ben Beispiel', status: 'invited', email: 'ben@example.com' },
    ],
    createdBy: 'tester@example.com',
    updatedBy: 'tester@example.com',
  });
  const questionnaires = await trainingQuestionnairesAll();
  const assigned = questionnaires.filter((q) => q.trainingId === training.id);
  assert.equal(assigned.length, 1);
  assert.equal(assigned[0].participantId, training.participants[0].id);
});
