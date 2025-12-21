export function normalizeYear(input) {
  const parsed = Number(input || 0);
  if (!Number.isFinite(parsed) || parsed <= 0) return null;
  return Math.trunc(parsed);
}

export function mapStatusClass(rawClass, score) {
  const normalized = String(rawClass || '').trim().toUpperCase();
  if (['A', 'B', 'C', 'D'].includes(normalized)) return normalized;
  if (['E', 'F'].includes(normalized)) return 'D';
  if (Number.isFinite(score)) {
    if (score <= 2.0) return 'A';
    if (score <= 3.0) return 'B';
    if (score <= 4.0) return 'C';
    return 'D';
  }
  return null;
}

export function decisionForClass(statusClass) {
  switch (statusClass) {
    case 'A':
      return 'weiterhin zugelassen';
    case 'B':
      return 'zugelassen mit Beobachtung / Maßnahmen';
    case 'C':
      return 'nur eingeschränkt / Freigabe erforderlich';
    case 'D':
      return 'gesperrt / disqualifiziert';
    default:
      return '';
  }
}

export function evaluationScore(evaluation) {
  const aggregates = evaluation?.aggregates || {};
  const score = aggregates.averageGrade ?? aggregates.averageScore ?? aggregates.score ?? null;
  return Number.isFinite(score) ? Number(score) : null;
}

export function pickEvaluation(evaluations, year) {
  if (!Array.isArray(evaluations) || evaluations.length === 0) return null;
  const active = evaluations.filter((e) => !e.archivedAt);
  if (year) {
    const candidates = active.filter((e) => Number(e.evalYear) === Number(year));
    if (!candidates.length) return null;
    const finals = candidates.filter((e) => String(e.status).toLowerCase() == 'final');
    const list = finals.length ? finals : candidates;
    return list.sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0))[0];
  }
  const finals = active.filter((e) => String(e.status).toLowerCase() == 'final');
  if (finals.length) {
    return finals.sort((a, b) => (b.evalYear || 0) - (a.evalYear || 0))[0];
  }
  return active.sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0))[0] || null;
}

export function evaluationState(evaluation) {
  if (!evaluation) return 'none';
  return String(evaluation.status).toLowerCase() === 'final' ? 'final' : 'draft';
}

export function evaluationWindow(evaluation, year) {
  if (evaluation?.periodFrom && evaluation?.periodTo) {
    return { from: Number(evaluation.periodFrom), to: Number(evaluation.periodTo) };
  }
  if (year) {
    const from = Date.UTC(year, 0, 1, 0, 0, 0);
    const to = Date.UTC(year, 11, 31, 23, 59, 59);
    return { from, to };
  }
  return null;
}

export function nextDueDate(evaluation, year) {
  if (!evaluation && !year) return null;
  const window = evaluationWindow(evaluation, year);
  if (!window) return null;
  const end = window.to;
  const due = new Date(end);
  due.setUTCFullYear(due.getUTCFullYear() + 1);
  return due.toISOString();
}

export function evidenceCounts(entries, escalations, window) {
  const perfCasesIncluded = entries.filter((entry) => {
    if (!entry.includeInAnnual) return false;
    if (entry.status && String(entry.status).toUpperCase() !== 'ABGESCHLOSSEN') return false;
    if (!window) return true;
    return entry.date >= window.from && entry.date <= window.to;
  }).length;

  let complaints = 0;
  let capas = 0;
  for (const entry of entries) {
    if (window && (entry.date < window.from || entry.date > window.to)) continue;
    const ref = String(entry.referenceType || '').toLowerCase();
    if (ref.includes('complaint') || ref.includes('reklam')) complaints += 1;
    if (ref.includes('capa') || ref.includes('8d')) capas += 1;
  }

  const escalationCount = escalations.filter((esc) => {
    if (!window) return true;
    const createdAt = Number(esc.createdAt || 0);
    if (!createdAt) return false;
    return createdAt >= window.from && createdAt <= window.to;
  }).length;

  return {
    perfCasesIncluded,
    complaints,
    capas,
    escalations: escalationCount,
  };
}

export function lastChangeFromSupplier(supplier) {
  const history = Array.isArray(supplier.history) ? supplier.history : [];
  if (!history.length) return null;
  const last = history[history.length - 1];
  if (!last || typeof last !== 'object') return null;
  return {
    action: last.action || '',
    actor: last.actor || '',
    at: last.at || last.updatedAt || null,
    note: last.note || '',
  };
}

export function buildApprovedSupplier({
  supplier,
  evaluations,
  entries,
  escalations,
  year,
  snapshot,
  previousEvaluation,
}) {
  const evaluation = pickEvaluation(evaluations, year);
  const state = evaluationState(evaluation);
  const evaluationYearUsed = evaluation?.evalYear || year || null;
  const score = evaluationScore(evaluation);
  const statusClass = mapStatusClass(evaluation?.aggregates?.classification, score);
  const decisionText = evaluation?.decision || decisionForClass(statusClass);
  const lastFinalizedAt = state === 'final' && evaluation?.updatedAt ? new Date(evaluation.updatedAt).toISOString() : null;
  const window = evaluationWindow(evaluation, evaluationYearUsed);
  const counts = evidenceCounts(entries, escalations, window);
  const prevScore = evaluationScore(previousEvaluation);
  const scoreTrend = Number.isFinite(score) && Number.isFinite(prevScore) ? Number((score - prevScore).toFixed(2)) : null;

  return {
    supplierId: supplier.id,
    name: supplier.name,
    supplierNo: supplier.supplierNumber,
    isCritical: supplier.critical === true,
    correspondenceLanguage: supplier.correspondenceLanguage || 'DE',
    statusClass,
    decisionText,
    score,
    scoreTrend,
    evaluationYearUsed,
    evaluationState: state,
    lastFinalizedAt,
    nextDueDate: nextDueDate(evaluation, evaluationYearUsed),
    counts,
    lastChange: lastChangeFromSupplier(supplier),
    adminNote: snapshot?.adminNote || '',
    reviewedBy: snapshot?.reviewedBy || '',
    reviewedAt: snapshot?.reviewedAt || null,
  };
}
