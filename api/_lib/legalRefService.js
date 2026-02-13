export const MDR_EU_LEX_CELEX = '32017R0745';
export const MDR_EU_LEX_PERMALINK = `https://eur-lex.europa.eu/legal-content/DE/ALL/?uri=CELEX:${MDR_EU_LEX_CELEX}`;

const CLASSIFICATION_RULE_TITLES = {
  1: 'Nicht-invasive Produkte',
  2: 'Nicht-invasive Produkte zur Leitung/Speicherung',
  3: 'Nicht-invasive Produkte zur Veränderung biologischer/chemischer Zusammensetzung',
  4: 'Nicht-invasive Produkte mit Kontakt zu verletzter Haut',
  5: 'Invasive Produkte in Körperöffnungen (nicht chirurgisch)',
  6: 'Kurzzeitig invasive Produkte in Körperöffnungen',
  7: 'Kurzzeitig chirurgisch-invasive Produkte',
  8: 'Langzeitig chirurgisch-invasive Produkte',
  9: 'Aktive therapeutische Produkte',
  10: 'Aktive diagnostische/überwachende Produkte',
  11: 'Software zur Entscheidungsunterstützung/Überwachung',
  12: 'Aktive Produkte zur Verabreichung/Entfernung von Stoffen',
  13: 'Alle Produkte mit integrierter Arzneimittel-Komponente',
  14: 'Kontrazeptive Produkte und STI-Schutz',
  15: 'Produkte zur Reinigung/Desinfektion/Sterilisation',
  16: 'Produkte mit tierischem Gewebe oder Derivaten',
  17: 'Produkte aus nicht lebensfähigem menschlichem Gewebe',
  18: 'Produkte mit nanomaterialbasiertem Kontakt',
  19: 'Produkte zur Aufnahme/Inhalation von Arzneimitteln',
  20: 'Invasive Produkte zur Verabreichung von Arzneimitteln',
  21: 'Stoffe/Substanzen zur Aufnahme durch den Körper',
  22: 'Aktive Produkte mit diagnostischer Funktion für vitale Prozesse',
};

export const MDR_CLASSIFICATION_RULES = Array.from({ length: 22 }, (_, i) => {
  const no = i + 1;
  return {
    id: `MDR_RULE_${no}`,
    rule_no: no,
    title_short: CLASSIFICATION_RULE_TITLES[no] || `Regel ${no}`,
    mdr_ref: `MDR Anhang VIII, Kapitel III, Regel ${no}`,
    eu_lex_link: MDR_EU_LEX_PERMALINK,
    rule_text_excerpt: `Kernaussage der Regel ${no} gemäß MDR Anhang VIII.`,
  };
});

export function resolveMdrClassificationRule(ruleNo) {
  const parsed = Number(ruleNo);
  if (!Number.isFinite(parsed) || parsed < 1 || parsed > 22) return null;
  return MDR_CLASSIFICATION_RULES.find((item) => item.rule_no === parsed) || null;
}

export function buildMdrRuleReference(ruleNo) {
  const rule = resolveMdrClassificationRule(ruleNo);
  if (!rule) return null;
  return {
    type: 'ExternalLink',
    referenceType: 'EU_Lex_MDR',
    label: `${rule.mdr_ref} (${rule.title_short})`,
    url: rule.eu_lex_link,
    refId: rule.id,
    metaJson: { auto: true, mdrRef: rule.mdr_ref, ruleNo: rule.rule_no },
  };
}

export function legalReferenceResolver(referenceType, value) {
  if (referenceType === 'MDR_CLASSIFICATION_RULE') {
    return resolveMdrClassificationRule(value);
  }
  return null;
}
