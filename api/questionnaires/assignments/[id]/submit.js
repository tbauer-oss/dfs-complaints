// /api/questionnaires/assignments/[id]/submit – Submit questionnaire answers
export const config = { runtime: 'nodejs' };

import { handlePreflight, setCors, ok, bad, methodNotAllowed, readJson } from '../../../_lib/http.js';
import { requirePortalAccess } from '../../../admin/_guard.js';
import { isAdminUser } from '../../../_lib/portalAuth.js';
import {
  trainingQuestionnaireGet,
  trainingQuestionnaireUpdate,
  trainingTemplateGet,
  trainingQuestionnairesAll,
  trainingRecordGet,
  trainingRecordUpdate,
} from '../../../_lib/store.js';

const TRAINING_TILE = 'trainings';

function scoreQuestionnaire(template, answers = [], thresholdPercent) {
  const answerMap = new Map(
    answers.map((a) => [
      (a.questionId || '').toString(),
      {
        selectedOptionIds: Array.isArray(a.selectedOptionIds) ? a.selectedOptionIds.map((id) => id.toString()) : [],
        freeText: (a.freeText ?? a.value ?? '').toString(),
      },
    ]),
  );

  let maxPoints = 0;
  let achievedPoints = 0;
  const evaluatedAnswers = [];

  const questions = Array.isArray(template?.questions) ? template.questions : [];
  for (const question of questions) {
    const qType = (question.type || 'text').toString();
    const qPoints = Number(question.points || 0) || 0;
    const answer = answerMap.get(question.id) || { selectedOptionIds: [], freeText: '' };
    let isCorrect = null;
    let pointsAchieved = 0;

    if (qType === 'single_choice' || qType === 'multi_choice') {
      maxPoints += qPoints;
      const correctIds = (question.options || [])
        .filter((opt) => opt && opt.isCorrect)
        .map((opt) => opt.id);
      const selectedIds = answer.selectedOptionIds;
      if (correctIds.length) {
        if (qType === 'single_choice') {
          isCorrect = selectedIds.length === 1 && correctIds.includes(selectedIds[0]);
        } else {
          const correctSet = new Set(correctIds);
          const selectedSet = new Set(selectedIds);
          isCorrect = selectedSet.size === correctSet.size && [...selectedSet].every((id) => correctSet.has(id));
        }
      } else {
        isCorrect = false;
      }
      if (isCorrect) pointsAchieved = qPoints;
    }

    achievedPoints += pointsAchieved;
    evaluatedAnswers.push({
      questionId: question.id,
      selectedOptionIds: answer.selectedOptionIds,
      freeText: answer.freeText,
      isCorrect,
      pointsAchieved,
    });
  }

  const scorePercent = maxPoints > 0 ? Math.round((achievedPoints / maxPoints) * 100) : 0;
  const threshold = Number(thresholdPercent ?? template?.defaultThresholdPercent ?? 70);
  const hasScore = maxPoints > 0;
  const passed = hasScore ? scorePercent >= threshold : true;

  return { maxPoints, achievedPoints, scorePercent, thresholdPercent: threshold, passed, hasScore, evaluatedAnswers };
}

export default async function handler(req, res) {
  if (handlePreflight(req, res)) return;
  setCors(req, res);

  if (req.method !== 'POST') return methodNotAllowed(res);

  const actor = await requirePortalAccess(req, res, { tile: TRAINING_TILE });
  if (!actor) return;

  try {
    const id = (req.query?.id || '').toString();
    if (!id) return bad(res, 'id missing', 400);

    const assignment = await trainingQuestionnaireGet(id);
    if (!assignment) return bad(res, 'not found', 404);

    const isAdmin = isAdminUser(actor);
    const actorId = (actor.email || '').toString().toLowerCase();
    const assignedId = (assignment.assignedToUserId || assignment.participantId || '').toLowerCase();
    if (!isAdmin && (!assignedId || assignedId !== actorId)) return bad(res, 'forbidden', 403);

    const body = readJson(req) || {};
    const answers = Array.isArray(body.answers) ? body.answers : [];
    const template = await trainingTemplateGet(assignment.templateId);
    if (!template) return bad(res, 'template missing', 400);

    const scoring = scoreQuestionnaire(template, answers, assignment.thresholdPercent);

    const status = scoring.hasScore ? (scoring.passed ? 'passed' : 'failed') : 'submitted';
    const now = Date.now();
    const updated = await trainingQuestionnaireUpdate(assignment.id, {
      status,
      submittedAt: now,
      scorePercent: scoring.scorePercent,
      maxPoints: scoring.maxPoints,
      achievedPoints: scoring.achievedPoints,
      thresholdPercent: scoring.thresholdPercent,
      needsRetraining: scoring.hasScore ? !scoring.passed : false,
      answers: scoring.evaluatedAnswers,
      updatedBy: actor.email,
    });

    if (assignment.trainingId) {
      const training = await trainingRecordGet(assignment.trainingId);
      if (training) {
        const participants = Array.isArray(training.participants) ? training.participants : [];
        const updatedParticipants = participants.map((p) => {
          if (p.id !== assignment.participantId) return p;
          if (!scoring.hasScore || scoring.passed) return p;
          return { ...p, status: 'retrainingRequired' };
        });

        const allAssignments = await trainingQuestionnairesAll();
        const wkAssignments = allAssignments.filter(
          (entry) => entry.trainingId === assignment.trainingId && entry.purpose === 'wk',
        );
        const allSubmitted = wkAssignments.length
          ? wkAssignments.every((entry) => ['passed', 'failed', 'submitted', 'evaluated'].includes(entry.status))
          : false;
        const nextWkStatus = allSubmitted ? 'done' : training.wkStatus;
        const nextWkCompletedAt = allSubmitted ? now : training.wkCompletedAt;

        await trainingRecordUpdate(training.id, {
          participants: updatedParticipants,
          wkStatus: nextWkStatus,
          wkCompletedAt: nextWkCompletedAt,
          updatedBy: actor.email,
        });
      }
    }

    return ok(res, {
      ok: true,
      assignment: updated,
      result: {
        scorePercent: scoring.scorePercent,
        maxPoints: scoring.maxPoints,
        achievedPoints: scoring.achievedPoints,
        thresholdPercent: scoring.thresholdPercent,
        passed: scoring.passed,
        hasScore: scoring.hasScore,
      },
    });
  } catch (err) {
    console.error('[questionnaires/submit] error', err);
    return bad(res, 'server error', 500);
  }
}
