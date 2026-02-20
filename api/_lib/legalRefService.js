export const MDR_DOCUMENT_SLUG = 'mdr-2017-745';
export const MDR_REFERENCE_ENDPOINT = `/api/regulatory/${MDR_DOCUMENT_SLUG}/sections`;

export const MDR_CLASSIFICATION_RULES = [
  { rule_no: 1, title_short: 'Nicht invasive Produkte', mdr_ref: 'MDR Anhang VIII, Regel 1', section_key: 'Annex_VIII_Rule_1' },
  { rule_no: 2, title_short: 'Kanalisierende nicht invasive Produkte', mdr_ref: 'MDR Anhang VIII, Regel 2', section_key: 'Annex_VIII_Rule_2' },
  { rule_no: 3, title_short: 'Biologische/chemische Veränderung', mdr_ref: 'MDR Anhang VIII, Regel 3', section_key: 'Annex_VIII_Rule_3' },
  { rule_no: 4, title_short: 'Invasive Produkte (Körperöffnungen)', mdr_ref: 'MDR Anhang VIII, Regel 4', section_key: 'Annex_VIII_Rule_4' },
  { rule_no: 11, title_short: 'Software für Diagnose/Therapie', mdr_ref: 'MDR Anhang VIII, Regel 11', section_key: 'Annex_VIII_Rule_11' },
];

export function resolveMdrClassificationRule(value) {
  const ruleNo = Number.parseInt(String(value || ''), 10);
  if (!Number.isFinite(ruleNo)) return null;
  return MDR_CLASSIFICATION_RULES.find((rule) => rule.rule_no === ruleNo) || null;
}

export function buildMdrRuleReference(value) {
  const rule = resolveMdrClassificationRule(value);
  if (!rule) return null;
  return {
    type: 'legal',
    label: `MDR Regel ${rule.rule_no}`,
    refId: `MDR_RULE_${rule.rule_no}`,
    legal_document_slug: MDR_DOCUMENT_SLUG,
    legal_reference_endpoint: MDR_REFERENCE_ENDPOINT,
    section_key: rule.section_key,
    note: rule.mdr_ref,
    metaJson: {
      auto: true,
      ruleNo: rule.rule_no,
      documentSlug: MDR_DOCUMENT_SLUG,
      sectionKey: rule.section_key,
    },
  };
}

export function legalReferenceResolver(type, value) {
  if (String(type || '').trim().toUpperCase() !== 'MDR_CLASSIFICATION_RULE') return null;
  const rule = resolveMdrClassificationRule(value);
  if (!rule) return null;
  return {
    type: 'MDR_CLASSIFICATION_RULE',
    value: String(rule.rule_no),
    title: `MDR Regel ${rule.rule_no}`,
    mdr_ref: rule.mdr_ref,
    document_slug: MDR_DOCUMENT_SLUG,
    section_key: rule.section_key,
    legal_reference_endpoint: MDR_REFERENCE_ENDPOINT,
  };
}

export function withLegalReference(entry = {}) {
  return {
    ...entry,
    legal_document_slug: MDR_DOCUMENT_SLUG,
    legal_reference_endpoint: MDR_REFERENCE_ENDPOINT,
  };
}
