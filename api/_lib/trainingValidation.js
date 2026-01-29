// api/_lib/trainingValidation.js – Validation helpers for training module
export const TRAINING_NEED_DEPARTMENTS = [
  'Gesamte Organisation',
  'Gesamte Produktion',
  'Produktion 1',
  'Produktion 2',
  'Abt. Schleiferei',
  'Abt. Chemie / Logistik',
  'Abt. Sinterei',
  'Abt. Bürstenproduktion',
  'Abt. Sonderwerkzeuge',
  'Abt. Galvanik',
  'Abt. Galvanik Vor-/Nachbereitung',
  'Abt. Dreherei',
  'Abt. Werkzeugbau',
  'Versand',
  'Vertrieb',
  'Einkauf',
  'Geschäftsleitung',
  'Human Ressources / Personal',
  'Finanzen',
  'Sonstiges...',
];

export const TRAINING_FORMATS = ['praesenz', 'online'];
export const PLANNED_PERIOD_TYPES = ['date', 'month', 'quarter', 'halfYear'];
export const INTERVAL_TYPES = ['once', 'recurring'];
export const INTERVAL_OPTIONS = [
  'vierteljährlich',
  'halbjährlich',
  'jährlich',
  'alle 2 Jahre',
  'alle 3 Jahre',
  'alle 4 Jahre',
  'alle 5 Jahre',
  'Sonstiges...',
];
export const TRAINING_PROGRAM_STATUSES = [
  'planned',
  'inProgress',
  'completed',
  'cancelled',
  'notOccurred',
  'removed',
  'abgebrochen',
];

export function trim(value) {
  return typeof value === 'string' ? value.trim() : '';
}

export function isValidYear(value) {
  return /^\d{4}$/.test(value);
}

export function normalizePeriodValue(type, value) {
  const val = trim(value);
  if (!val) return null;
  if (type === 'date' && /^\d{4}-\d{2}-\d{2}$/.test(val)) return val;
  if (type === 'month' && /^\d{4}-\d{2}$/.test(val)) return val;
  if (type === 'quarter' && /^\d{4}-Q[1-4]$/.test(val)) return val;
  if (type === 'halfYear' && /^\d{4}-H[1-2]$/.test(val)) return val;
  return null;
}

export function periodYear(value) {
  if (!value || value.length < 4) return '';
  return value.slice(0, 4);
}

export function validateTrainingNeed(body = {}) {
  const errors = {};
  const yearValue = String(body.year || '').trim();
  if (!isValidYear(yearValue)) errors.year = 'Bitte ein gültiges Schulungsjahr (YYYY) angeben.';
  if (!trim(body.contactName)) errors.contactName = 'Ansprechpartner ist erforderlich.';

  const deptSelected = trim(body.departmentTeamSelected);
  if (!deptSelected) {
    errors.departmentTeamSelected = 'Abteilung/Team ist erforderlich.';
  } else if (!TRAINING_NEED_DEPARTMENTS.includes(deptSelected)) {
    errors.departmentTeamSelected = 'Bitte gültige Abteilung/Team Auswahl treffen.';
  }
  if (deptSelected === 'Sonstiges...') {
    const freeText = trim(body.departmentTeamFreeText);
    if (freeText.length < 2) errors.departmentTeamFreeText = 'Bitte Abteilung/Team angeben (mind. 2 Zeichen).';
  }

  const periodType = trim(body.plannedPeriodType);
  if (!PLANNED_PERIOD_TYPES.includes(periodType)) {
    errors.plannedPeriodType = 'Bitte Zeitraumstyp auswählen.';
  }
  const normalizedPeriod = normalizePeriodValue(periodType, body.plannedPeriodValue);
  if (!normalizedPeriod) {
    errors.plannedPeriodValue = 'Bitte Zeitraum vollständig angeben.';
  } else if (yearValue && periodYear(normalizedPeriod) !== yearValue) {
    errors.plannedPeriodValue = 'Bitte Zeitraum vollständig angeben.';
  }

  const format = trim(body.trainingFormat);
  if (!TRAINING_FORMATS.includes(format)) {
    errors.trainingFormat = 'Bitte Format auswählen.';
  }

  const intervalType = trim(body.intervalType);
  if (!INTERVAL_TYPES.includes(intervalType)) {
    errors.intervalType = 'Bitte Schulungsintervall auswählen.';
  }
  if (intervalType === 'recurring') {
    const intervalValue = trim(body.intervalValue);
    if (!intervalValue) {
      errors.intervalValue = 'Bitte Intervall auswählen.';
    } else if (!INTERVAL_OPTIONS.includes(intervalValue)) {
      errors.intervalValue = 'Bitte gültiges Intervall auswählen.';
    }
    if (intervalValue === 'Sonstiges...') {
      const intervalFree = trim(body.intervalValueFreeText);
      if (intervalFree.length < 2) errors.intervalValueFreeText = 'Bitte Intervall angeben (mind. 2 Zeichen).';
    }
  }

  const items = Array.isArray(body.items) ? body.items : [];
  const primaryItem = items[0] || {};
  if (!trim(primaryItem.topic)) {
    errors.topic = 'Schulungsthema ist erforderlich.';
  }
  const participants = Number(primaryItem.participants || 0);
  if (!Number.isFinite(participants) || participants <= 0) {
    errors.participants = 'Teilnehmer muss eine gültige Zahl sein.';
  }

  const budgetRaw = body.plannedBudget;
  if (budgetRaw !== null && budgetRaw !== undefined && budgetRaw !== '') {
    const budget = Number(budgetRaw);
    if (!Number.isFinite(budget) || budget < 0) {
      errors.plannedBudget = 'Geplantes Budget muss eine gültige Zahl sein.';
    }
  }

  return { errors, normalizedPeriod };
}

export function validateTrainingProgram(body = {}) {
  const errors = {};
  const yearValue = String(body.year || '').trim();
  if (!isValidYear(yearValue)) errors.year = 'Bitte ein gültiges Programmjahr (YYYY) angeben.';
  if (!trim(body.title)) errors.title = 'Thema ist erforderlich.';
  if (!trim(body.department)) errors.department = 'Abteilung/Team ist erforderlich.';
  if (!trim(body.targetGroup)) errors.targetGroup = 'Zielgruppe ist erforderlich.';

  const periodType = trim(body.plannedPeriodType);
  if (!PLANNED_PERIOD_TYPES.includes(periodType)) {
    errors.plannedPeriodType = 'Bitte Zeitraumstyp auswählen.';
  }
  const normalizedPeriod = normalizePeriodValue(periodType, body.plannedPeriodValue);
  if (!normalizedPeriod) {
    errors.plannedPeriodValue = 'Bitte Zeitraum vollständig angeben.';
  } else if (yearValue && periodYear(normalizedPeriod) !== yearValue) {
    errors.plannedPeriodValue = 'Der Zeitraum muss im ausgewählten Jahr liegen.';
  }

  const format = trim(body.format);
  if (!TRAINING_FORMATS.includes(format)) {
    errors.format = 'Bitte Format auswählen.';
  }
  if (!trim(body.responsiblePerson)) errors.responsiblePerson = 'Verantwortlich ist erforderlich.';
  if (!trim(body.participantsPlanned)) errors.participantsPlanned = 'Teilnehmer (geplant) ist erforderlich.';

  const status = trim(body.status || 'planned');
  if (status && !TRAINING_PROGRAM_STATUSES.includes(status)) {
    errors.status = 'Bitte gültigen Status auswählen.';
  }
  if (['cancelled', 'notOccurred', 'removed', 'abgebrochen'].includes(status)) {
    const reason = trim(body.cancellationReason);
    if (reason.length < 5) {
      errors.cancellationReason = 'Begründung muss mindestens 5 Zeichen enthalten.';
    }
  }

  return { errors, normalizedPeriod };
}
