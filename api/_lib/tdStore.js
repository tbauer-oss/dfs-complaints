import crypto from 'node:crypto';
import PDFDocument from 'pdfkit';
import { Redis } from '@upstash/redis';
import { fmeaAll, capaAll, complaintsAll, supplierAll, trainingRecordsAll, gsprAssessmentsByTd } from './store.js';
import { getUniqueMdrTdEntries } from './products.js';

const REDIS_URL =
  process.env.UPSTASH_REDIS_REST_KV_REST_API_URL ||
  process.env.UPSTASH_REDIS_REST_URL ||
  process.env.KV_REST_API_URL ||
  process.env.REDIS_URL ||
  null;
const REDIS_TOKEN =
  process.env.UPSTASH_REDIS_REST_KV_REST_API_TOKEN ||
  process.env.UPSTASH_REDIS_REST_TOKEN ||
  process.env.KV_REST_API_TOKEN ||
  process.env.REDIS_TOKEN ||
  null;

const PREFIX = 'dfs:td:';
const KEY_ALL = `${PREFIX}all`;
const KEY_SECTIONS = `${PREFIX}sections`;
const KEY_LINKS = `${PREFIX}links`;
const KEY_CHANGES = `${PREFIX}changes`;
const KEY_IMPACTS = `${PREFIX}impacts`;
const KEY_EXPORTS = `${PREFIX}exports`;
const KEY = (id) => `${PREFIX}file:${id}`;
const KEY_SECTION = (id) => `${PREFIX}section:${id}`;
const KEY_LINK = (id) => `${PREFIX}link:${id}`;
const KEY_CHANGE = (id) => `${PREFIX}change:${id}`;
const KEY_IMPACT = (id) => `${PREFIX}impact:${id}`;
const KEY_EXPORT = (id) => `${PREFIX}export:${id}`;
const KEY_CONTENT = `${PREFIX}section-content`;
const KEY_SECTION_CONTENT = (id) => `${PREFIX}section-content:${id}`;

const lifecycleStates = new Set(['Development', 'Released', 'PostMarket', 'Update', 'Sunset', 'Obsolete']);
const tdStatus = new Set(['Green', 'Yellow', 'Red', 'Draft']);
const sectionStatus = new Set(['NotStarted', 'InProgress', 'Complete', 'Blocked', 'NotApplicable']);
const linkTypes = new Set(['Document', 'GSPR', 'FMEA', 'CAPA', 'ComplaintMetric', 'Supplier', 'Training', 'ExternalLink', 'Report']);
const changeTypes = new Set(['Material', 'Supplier', 'Geometry', 'Coating', 'IntendedPurpose', 'LabelingIFU', 'Classification', 'Process', 'Software', 'Other']);
const severities = new Set(['Low', 'Medium', 'High', 'Critical']);
const changeStatuses = new Set(['Draft', 'Submitted', 'UnderReview', 'Approved', 'Rejected', 'Implemented']);
const impactTypes = new Set(['GSPR', 'FMEA', 'ClinicalEvaluation', 'PMS', 'LabelingIFU', 'VerificationValidation', 'SupplierAudit', 'Training', 'TechnicalSpecs', 'Other']);
const impactStatuses = new Set(['Open', 'InProgress', 'Done', 'NotApplicable']);

let _redis = null;
function redis() {
  if (_redis) return _redis;
  if (!REDIS_URL || !REDIS_TOKEN) return null;
  _redis = new Redis({ url: REDIS_URL, token: REDIS_TOKEN });
  return _redis;
}

const mem = {
  ids: new Set(),
  sectionIds: new Set(),
  linkIds: new Set(),
  changeIds: new Set(),
  impactIds: new Set(),
  exportIds: new Set(),
  sectionContentIds: new Set(),
  files: new Map(),
  sections: new Map(),
  links: new Map(),
  changes: new Map(),
  impacts: new Map(),
  exports: new Map(),
  sectionContents: new Map(),
};

const nowIso = () => new Date().toISOString();
const cuid = (prefix) => `${prefix}_${crypto.randomUUID().replace(/-/g, '').slice(0, 16)}`;
const asArray = (v) => (Array.isArray(v) ? v : []);
const asStringArray = (v) => asArray(v).map((x) => String(x || '').trim()).filter(Boolean);

const DEFAULT_SECTION_CONTENT = {
  summaryMarkdown: '',
  contentJson: null,
};

const SECTION_CONTENT_VALIDATORS = {
  ANNEX_II_A: (input) => ({
    intendedPurpose: String(input?.intendedPurpose || ''),
    deviceDescription: String(input?.deviceDescription || ''),
    variantsAccessories: String(input?.variantsAccessories || ''),
    udiBasic: String(input?.udiBasic || ''),
    classification: String(input?.classification || ''),
    rule: String(input?.rule || ''),
    principlesOfOperation: String(input?.principlesOfOperation || ''),
    references: asStringArray(input?.references),
  }),
  ANNEX_II_B: (input) => ({
    labelingRefs: asStringArray(input?.labelingRefs),
    ifuRefs: asStringArray(input?.ifuRefs),
    symbolsRefs: asStringArray(input?.symbolsRefs),
    translationsNotes: String(input?.translationsNotes || ''),
  }),
  ANNEX_II_C: (input) => ({
    manufacturingSites: asStringArray(input?.manufacturingSites),
    keyProcesses: asStringArray(input?.keyProcesses),
    criticalProcessControls: String(input?.criticalProcessControls || ''),
    subcontractorsRefs: asStringArray(input?.subcontractorsRefs),
  }),
  ANNEX_II_D: (input) => ({ ...input }),
  ANNEX_II_E: (input) => ({
    riskManagementSummary: String(input?.riskManagementSummary || ''),
    fmeaRefs: asStringArray(input?.fmeaRefs),
    benefitRiskConclusion: String(input?.benefitRiskConclusion || ''),
  }),
  ANNEX_II_F: (input) => ({
    standardsApplied: asStringArray(input?.standardsApplied),
    biocompatibilityRefs: asStringArray(input?.biocompatibilityRefs),
    cleaningSterilizationRefs: asStringArray(input?.cleaningSterilizationRefs),
    performanceTestingRefs: asStringArray(input?.performanceTestingRefs),
    softwareValidationRefs: asStringArray(input?.softwareValidationRefs),
  }),
  ANNEX_III_G: (input) => ({
    pmsPlanSummary: String(input?.pmsPlanSummary || ''),
    pmsPlanRefs: asStringArray(input?.pmsPlanRefs),
    pmsMethods: asStringArray(input?.pmsMethods),
  }),
  ANNEX_III_H: (input) => {
    const reportType = ['PMS_REPORT', 'PSUR', 'PMCF'].includes(String(input?.reportType || '')) ? String(input.reportType) : 'PMS_REPORT';
    return {
      reportType,
      reportingPeriod: String(input?.reportingPeriod || ''),
      keyFindings: String(input?.keyFindings || ''),
      actionsConclusions: String(input?.actionsConclusions || ''),
      reportRefs: asStringArray(input?.reportRefs),
    };
  },
};

export const TD_SECTION_TEMPLATES = [
  { key: 'ANNEX_II_A', name: 'A. Device description and specification', description: 'Including variants and accessories.', order: 10, annex: 'ANNEX_II' },
  { key: 'ANNEX_II_B', name: 'B. Information supplied by manufacturer', description: 'Labeling / IFU and claims.', order: 20, annex: 'ANNEX_II' },
  { key: 'ANNEX_II_C', name: 'C. Design and manufacturing information', description: 'Critical processes and manufacturing controls.', order: 30, annex: 'ANNEX_II' },
  { key: 'ANNEX_II_D', name: 'D. General Safety & Performance Requirements (GSPR)', description: 'Linked to GSPR assessments.', order: 40, annex: 'ANNEX_II' },
  { key: 'ANNEX_II_E', name: 'E. Benefit-risk and risk management', description: 'Linked to FMEA and risk files.', order: 50, annex: 'ANNEX_II' },
  { key: 'ANNEX_II_F', name: 'F. Product verification and validation', description: 'V&V, biocompatibility, sterilization, software as applicable.', order: 60, annex: 'ANNEX_II' },
  { key: 'ANNEX_III_G', name: 'G. PMS plan', description: 'Post-market surveillance planning.', order: 70, annex: 'ANNEX_III' },
  { key: 'ANNEX_III_H', name: 'H. PMS report / PSUR / PMCF', description: 'PMS outcomes and PMCF evidence as applicable.', order: 80, annex: 'ANNEX_III' },
];

function normalizeFile(input, actorEmail) {
  const code = String(input?.code || '').trim().toUpperCase();
  if (!code) throw new Error('code is required');
  const title = String(input?.title || '').trim();
  if (!title) throw new Error('title is required');
  const lifecycleState = lifecycleStates.has(input?.lifecycleState) ? input.lifecycleState : 'Development';
  return {
    id: String(input?.id || cuid('td')),
    code,
    title,
    productGroup: input?.productGroup ? String(input.productGroup) : null,
    classification: input?.classification ? String(input.classification) : null,
    rule: input?.rule ? String(input.rule) : null,
    lifecycleState,
    ownerUserId: input?.ownerUserId ? String(input.ownerUserId) : actorEmail || null,
    status: tdStatus.has(input?.status) ? input.status : 'Draft',
    lastReviewAt: input?.lastReviewAt || null,
    nextReviewAt: input?.nextReviewAt || null,
    createdAt: input?.createdAt || nowIso(),
    updatedAt: nowIso(),
    deletedAt: input?.deletedAt || null,
  };
}

function defaultSections(tdId, actorEmail) {
  const ts = nowIso();
  return TD_SECTION_TEMPLATES.map((tpl) => ({
    id: `${tdId}:${tpl.key}`,
    tdId,
    templateKey: tpl.key,
    name: tpl.name,
    order: tpl.order,
    status: 'NotStarted',
    lastUpdatedAt: ts,
    reviewCycleMonths: 12,
    nextReviewAt: null,
    ownerUserId: actorEmail || null,
    notes: null,
  }));
}

async function withStore(opRedis, opMem) {
  const client = redis();
  if (!client) return opMem();
  try {
    return await opRedis(client);
  } catch {
    return opMem();
  }
}

async function getIds() {
  return withStore((r) => r.smembers(KEY_ALL), () => Array.from(mem.ids));
}

async function putEntity(keyBuilder, id, value, map, trackSet = null, trackMemSet = null) {
  return withStore(
    async (r) => {
      await r.set(keyBuilder(id), value);
      if (trackSet) await r.sadd(trackSet, id);
      return value;
    },
    () => {
      map.set(id, value);
      if (trackMemSet) trackMemSet.add(id);
      return value;
    },
  );
}

async function getEntity(keyBuilder, id, map) {
  return withStore((r) => r.get(keyBuilder(id)), () => map.get(id) || null);
}


function deterministicTdId(code) {
  const safe = (code ?? '').toString().trim().toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
  return `td_seed_${safe || 'unknown'}`;
}

async function ensureSeedTdFiles() {
  const existing = await tdListRaw();
  const byCode = new Set(existing.map((entry) => entry.code));
  let createdAny = false;
  const catalog = await getUniqueMdrTdEntries().catch(() => []);
  for (const entry of catalog) {
    const code = String(entry?.code || '').trim().toUpperCase();
    if (!/^MDR-TD\d+$/i.test(code)) continue;
    if (byCode.has(code)) continue;
    const seeded = normalizeFile({
      id: deterministicTdId(code),
      code,
      title: entry?.title || entry?.label || code,
      productGroup: entry?.productGroup || null,
      classification: entry?.classification || null,
      rule: entry?.rule || null,
      lifecycleState: 'Development',
      status: 'Draft',
    }, null);
    await putEntity(KEY, seeded.id, seeded, mem.files, KEY_ALL, mem.ids);
    const sections = defaultSections(seeded.id, null);
    for (const section of sections) {
      await putEntity(KEY_SECTION, section.id, section, mem.sections, KEY_SECTIONS, mem.sectionIds);
      await tdSectionContentBackfill(section.id);
    }
    byCode.add(code);
    createdAny = true;
  }
  return createdAny;
}

async function tdListRaw() {
  const ids = await getIds();
  const out = [];
  for (const id of ids) {
    const td = await getEntity(KEY, id, mem.files);
    if (td && !td.deletedAt) out.push(td);
  }
  return out;
}

export async function tdList() {
  await ensureSeedTdFiles();
  const out = await tdListRaw();
  out.sort((a, b) => a.code.localeCompare(b.code, undefined, { numeric: true }));
  return out;
}

export async function tdGet(id) {
  await ensureSeedTdFiles();
  return getEntity(KEY, id, mem.files);
}

export async function tdCreate(input, actorEmail) {
  const normalized = normalizeFile(input, actorEmail);
  const existing = await tdList();
  if (existing.some((td) => td.code === normalized.code)) throw new Error('code must be unique');
  await putEntity(KEY, normalized.id, normalized, mem.files, KEY_ALL, mem.ids);
  const sections = defaultSections(normalized.id, actorEmail);
  for (const section of sections) {
    await putEntity(KEY_SECTION, section.id, section, mem.sections, KEY_SECTIONS, mem.sectionIds);
    await tdSectionContentBackfill(section.id);
  }
  return normalized;
}

export async function tdUpdate(id, patch) {
  const current = await tdGet(id);
  if (!current || current.deletedAt) throw new Error('TD not found');
  const next = normalizeFile({ ...current, ...patch, id: current.id, code: current.code, createdAt: current.createdAt }, current.ownerUserId);
  await putEntity(KEY, id, next, mem.files, KEY_ALL, mem.ids);
  return next;
}

export async function tdDelete(id) {
  const current = await tdGet(id);
  if (!current || current.deletedAt) throw new Error('TD not found');
  const next = { ...current, deletedAt: nowIso(), updatedAt: nowIso() };
  await putEntity(KEY, id, next, mem.files, KEY_ALL, mem.ids);
  return next;
}

export async function tdSections(tdId) {
  const ids = await withStore((r)=>r.smembers(KEY_SECTIONS), ()=>Array.from(mem.sectionIds));
  const sectionList = [];
  for (const id of ids) {
    const section = await getEntity(KEY_SECTION, id, mem.sections);
    if (section?.tdId === tdId) sectionList.push(section);
  }
  if (!sectionList.length) {
    const sections = defaultSections(tdId, null);
    for (const section of sections) {
      await putEntity(KEY_SECTION, section.id, section, mem.sections, KEY_SECTIONS, mem.sectionIds);
      await tdSectionContentBackfill(section.id);
    }
    return sections;
  }
  for (const section of sectionList) await tdSectionContentBackfill(section.id);
  return sectionList.sort((a, b) => a.order - b.order);
}

export async function tdSectionContentBackfill(sectionId) {
  const current = await getEntity(KEY_SECTION_CONTENT, sectionId, mem.sectionContents);
  if (current) return current;
  const next = {
    id: cuid('tdsc'),
    sectionId,
    summaryMarkdown: '',
    contentJson: null,
    updatedByUserId: null,
    createdAt: nowIso(),
    updatedAt: nowIso(),
  };
  await putEntity(KEY_SECTION_CONTENT, sectionId, next, mem.sectionContents, KEY_CONTENT, mem.sectionContentIds);
  return next;
}

export async function tdSectionContentGet(sectionId) {
  return tdSectionContentBackfill(sectionId);
}

export async function tdSectionContentPut(sectionId, payload, actorId) {
  const section = await getEntity(KEY_SECTION, sectionId, mem.sections);
  if (!section) throw new Error('section not found');
  const current = await tdSectionContentBackfill(sectionId);
  const validator = SECTION_CONTENT_VALIDATORS[section.templateKey] || ((x) => x || null);
  const summaryMarkdown = typeof payload?.summaryMarkdown === 'string' ? payload.summaryMarkdown : current.summaryMarkdown;
  const contentJson = payload?.contentJson === undefined ? current.contentJson : validator(payload.contentJson || {});
  const next = {
    ...current,
    sectionId,
    summaryMarkdown,
    contentJson,
    updatedByUserId: actorId || null,
    updatedAt: nowIso(),
  };
  await putEntity(KEY_SECTION_CONTENT, sectionId, next, mem.sectionContents, KEY_CONTENT, mem.sectionContentIds);
  await tdSectionUpdate(sectionId, {});
  return next;
}

export async function tdSectionGetDetailed(sectionId) {
  const section = await getEntity(KEY_SECTION, sectionId, mem.sections);
  if (!section) return null;
  const content = await tdSectionContentBackfill(sectionId);
  const links = (await tdLinks(section.tdId)).filter((l) => l.sectionId === sectionId);
  return { ...section, content, links };
}

export async function tdSectionUpdate(sectionId, patch) {
  const current = await getEntity(KEY_SECTION, sectionId, mem.sections);
  if (!current) throw new Error('section not found');
  const next = {
    ...current,
    ...patch,
    status: sectionStatus.has(patch?.status) ? patch.status : current.status,
    lastUpdatedAt: nowIso(),
  };
  await putEntity(KEY_SECTION, sectionId, next, mem.sections);
  return next;
}

export async function tdLinks(tdId) {
  const ids = await withStore((r)=>r.smembers(KEY_LINKS), ()=>Array.from(mem.linkIds));
  const links = [];
  for (const id of ids) {
    const link = await getEntity(KEY_LINK, id, mem.links);
    if (link?.tdId === tdId) links.push(link);
  }
  return links;
}

export async function tdLinksBySection(tdId, sectionId = null) {
  const all = await tdLinks(tdId);
  if (!sectionId) return all;
  return all.filter((l) => l.sectionId === sectionId);
}

export async function tdLinkCreate(tdId, payload) {
  const type = linkTypes.has(payload?.type) ? payload.type : 'Document';
  const label = String(payload?.label || '').trim();
  if (!label) throw new Error('label is required');
  const link = {
    id: cuid('tdl'),
    tdId,
    sectionId: payload?.sectionId || null,
    type,
    refId: String(payload?.refId || '').trim(),
    label,
    url: payload?.url ? String(payload.url) : null,
    metaJson: payload?.metaJson && typeof payload.metaJson === 'object' ? payload.metaJson : null,
    createdAt: nowIso(),
  };
  await putEntity(KEY_LINK, link.id, link, mem.links, KEY_LINKS, mem.linkIds);
  return link;
}

export async function tdLinkDelete(linkId) {
  return withStore(
    (r) => r.del(KEY_LINK(linkId)),
    () => {
      mem.links.delete(linkId);
      return 1;
    },
  );
}

export async function tdChangeCreate(tdId, payload, actor) {
  const title = String(payload?.title || '').trim();
  if (!title) throw new Error('title is required');
  const change = {
    id: cuid('tdc'),
    tdId,
    title,
    description: String(payload?.description || '').trim(),
    changeType: changeTypes.has(payload?.changeType) ? payload.changeType : 'Other',
    severity: severities.has(payload?.severity) ? payload.severity : 'Low',
    status: 'Draft',
    requestedByUserId: actor || null,
    reviewedByUserId: null,
    approvedByUserId: null,
    createdAt: nowIso(),
    updatedAt: nowIso(),
    implementedAt: null,
    requiresNbNotification: payload?.requiresNbNotification === true,
    rationale: payload?.rationale ? String(payload.rationale) : null,
  };
  await putEntity(KEY_CHANGE, change.id, change, mem.changes, KEY_CHANGES, mem.changeIds);
  return change;
}

export async function tdChanges(tdId) {
  const ids = await withStore((r)=>r.smembers(KEY_CHANGES), ()=>Array.from(mem.changeIds));
  const changes = [];
  for (const id of ids) {
    const change = await getEntity(KEY_CHANGE, id, mem.changes);
    if (change?.tdId === tdId) changes.push(change);
  }
  return changes.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

export async function tdChangeGet(changeId) {
  const change = await getEntity(KEY_CHANGE, changeId, mem.changes);
  if (!change) return null;
  const impacts = await tdImpactByChange(changeId);
  return { ...change, impactItems: impacts };
}

export async function tdChangePatch(changeId, patch, actor) {
  const current = await getEntity(KEY_CHANGE, changeId, mem.changes);
  if (!current) throw new Error('change not found');
  const status = changeStatuses.has(patch?.status) ? patch.status : current.status;
  const next = {
    ...current,
    ...patch,
    status,
    reviewedByUserId: status === 'UnderReview' ? actor || current.reviewedByUserId : current.reviewedByUserId,
    approvedByUserId: status === 'Approved' ? actor || current.approvedByUserId : current.approvedByUserId,
    implementedAt: status === 'Implemented' ? nowIso() : current.implementedAt,
    updatedAt: nowIso(),
  };
  await putEntity(KEY_CHANGE, changeId, next, mem.changes, KEY_CHANGES, mem.changeIds);
  return next;
}

export async function tdImpactByChange(changeRequestId) {
  const ids = await withStore((r)=>r.smembers(KEY_IMPACTS), ()=>Array.from(mem.impactIds));
  const items = [];
  for (const id of ids) {
    const it = await getEntity(KEY_IMPACT, id, mem.impacts);
    if (it?.changeRequestId === changeRequestId) items.push(it);
  }
  return items;
}


export async function tdImpactPatch(impactId, patch) {
  const current = await getEntity(KEY_IMPACT, impactId, mem.impacts);
  if (!current) throw new Error('impact not found');
  const next = {
    ...current,
    ...patch,
    status: impactStatuses.has(patch?.status) ? patch.status : current.status,
  };
  await putEntity(KEY_IMPACT, impactId, next, mem.impacts, KEY_IMPACTS, mem.impactIds);
  return next;
}

export async function tdAnalyzeChange(changeId) {
  const change = await getEntity(KEY_CHANGE, changeId, mem.changes);
  if (!change) throw new Error('change not found');
  const byType = {
    Material: [
      { impactType: 'FMEA', targetRef: `FMEA:${change.tdId}`, requiredAction: 'Review FMEA controls and scoring.' },
      { impactType: 'VerificationValidation', targetRef: 'ANNEX_II_F', requiredAction: 'Review biocompatibility and V&V evidence.' },
      { impactType: 'LabelingIFU', targetRef: 'ANNEX_II_B', requiredAction: 'Check IFU/labeling material references.' },
      { impactType: 'PMS', targetRef: 'ANNEX_III_G', requiredAction: 'Update PMS plan watchpoints for material change.' },
    ],
    Supplier: [
      { impactType: 'SupplierAudit', targetRef: 'SUPPLIER:AUDIT', requiredAction: 'Re-evaluate supplier qualification/audit.' },
      { impactType: 'VerificationValidation', targetRef: 'INCOMING_QC', requiredAction: 'Update incoming QC controls.' },
      { impactType: 'FMEA', targetRef: `FMEA:${change.tdId}`, requiredAction: 'Update supplier-linked failure modes.' },
      { impactType: 'PMS', targetRef: 'ANNEX_III_G', requiredAction: 'Add supplier monitoring signal in PMS.' },
    ],
    LabelingIFU: [
      { impactType: 'LabelingIFU', targetRef: 'ANNEX_II_B', requiredAction: 'Update IFU and labeling section B content.' },
      { impactType: 'Training', targetRef: 'TRAINING:COMMERCIAL', requiredAction: 'Update training and communication materials.' },
      { impactType: 'GSPR', targetRef: 'GSPR:AnnexI', requiredAction: 'Verify linked GSPR requirements remain compliant.' },
      { impactType: 'PMS', targetRef: 'ANNEX_III_G', requiredAction: 'Define PMS communication follow-up actions.' },
    ],
  };
  const blueprints = byType[change.changeType] || [
    { impactType: 'GSPR', targetRef: 'GSPR:AnnexI', requiredAction: 'Review impacted requirements.' },
    { impactType: 'FMEA', targetRef: `FMEA:${change.tdId}`, requiredAction: 'Review risk controls.' },
  ];
  const generated = [];
  for (const b of blueprints) {
    const item = {
      id: cuid('tdi'),
      changeRequestId: changeId,
      impactType: impactTypes.has(b.impactType) ? b.impactType : 'Other',
      targetRef: b.targetRef,
      requiredAction: b.requiredAction,
      status: 'Open',
    };
    await putEntity(KEY_IMPACT, item.id, item, mem.impacts, KEY_IMPACTS, mem.impactIds);
    generated.push(item);
  }
  await tdChangePatch(changeId, { status: 'UnderReview' }, change.requestedByUserId);
  return generated;
}

function computeReadinessStatus(score, reasons) {
  if (reasons.some((r) => r.toLowerCase().includes('critical'))) return 'Red';
  if (score >= 90 && !reasons.some((r) => r.toLowerCase().includes('overdue'))) return 'Green';
  return 'Yellow';
}

export async function tdComputedSummary(td) {
  const sections = await tdSections(td.id);
  const links = await tdLinks(td.id);
  const reasons = [];
  const today = Date.now();
  const blocked = sections.filter((s) => s.status === 'Blocked');
  if (blocked.length) reasons.push(`${blocked.length} section(s) blocked`);
  const overdueSections = sections.filter((s) => s.nextReviewAt && Date.parse(s.nextReviewAt) < today);
  if (overdueSections.length) reasons.push(`Annex sections overdue (${overdueSections.length})`);
  if (td.nextReviewAt && Date.parse(td.nextReviewAt) < today) reasons.push('TD review overdue');

  const hasGspr = links.some((l) => l.type === 'GSPR' && l.sectionId?.includes('ANNEX_II_D'));
  const hasFmea = links.some((l) => l.type === 'FMEA' && l.sectionId?.includes('ANNEX_II_E'));
  const hasPms = links.some((l) => (l.type === 'Report' || l.type === 'Document') && (l.sectionId?.includes('ANNEX_III_G') || l.sectionId?.includes('ANNEX_III_H')));
  if (!hasGspr) reasons.push('Missing mandatory link: GSPR');
  if (!hasFmea) reasons.push('Missing mandatory link: FMEA');
  if (!hasPms) reasons.push('Missing mandatory link: PMS plan/report');

  const gspr = asArray(await gsprAssessmentsByTd(td.id));
  const gsprAssessed = gspr.length ? Math.round((gspr.filter((x) => x.status && x.status !== 'open').length / gspr.length) * 100) : 0;

  const fmeas = asArray(await fmeaAll()).filter((f) => f.mdrTd === td.code || f.mdrTd === td.id);
  const capa = asArray(await capaAll()).filter((c) => c.tdId === td.id || c.mdrTd === td.code);
  const complaints = asArray(await complaintsAll()).filter((c) => c.productGroup && c.productGroup === td.productGroup);
  const suppliers = asArray(await supplierAll()).filter((s) => links.some((l) => l.type === 'Supplier' && l.refId === s.id));
  const trainings = asArray(await trainingRecordsAll()).filter((tr) => links.some((l) => l.type === 'Training' && l.refId === tr.id));

  const openCriticalCapa = capa.filter((c) => c.status !== 'closed' && String(c.severity || '').toLowerCase().includes('critical')).length;
  if (openCriticalCapa) reasons.push('Open CAPA critical');

  const score = Math.max(0, Math.min(100,
    (hasFmea ? 20 : 0) +
    Math.round(gsprAssessed * 0.2) +
    (links.some((l) => l.label.toLowerCase().includes('clinical')) ? 20 : 0) +
    (sections.filter((s) => s.templateKey.startsWith('ANNEX_III_') && s.status === 'Complete').length >= 1 ? 15 : 0) +
    (suppliers.length ? 10 : 0) +
    (trainings.length ? 5 : 0) +
    (openCriticalCapa ? 0 : 10)
  ));

  return {
    complianceScore: score,
    readinessStatus: computeReadinessStatus(score, reasons),
    reasons: reasons.slice(0, 5),
    overdueReviews: overdueSections.length + (td.nextReviewAt && Date.parse(td.nextReviewAt) < today ? 1 : 0),
    openCapaCount: capa.filter((c) => String(c.status || '').toLowerCase() !== 'closed').length,
    openCriticalGaps: blocked.length + openCriticalCapa,
    complaintTrend: {
      total: complaints.length,
      recent30d: complaints.filter((c) => {
        const ts = Date.parse(c.createdAt || c.date || '');
        return Number.isFinite(ts) && today - ts <= 1000 * 60 * 60 * 24 * 30;
      }).length,
    },
    breakdown: {
      riskManagement: hasFmea ? 100 : 0,
      gsprCompletion: gsprAssessed,
      clinicalEvaluation: links.some((l) => l.label.toLowerCase().includes('clinical')) ? 100 : 0,
      pmsPmcf: hasPms ? 100 : 0,
      supplierControls: suppliers.length ? 100 : 0,
      trainingEvidence: trainings.length ? 100 : 0,
      capaFindings: openCriticalCapa ? 0 : 100,
      fmeaCount: fmeas.length,
    },
  };
}

export async function tdReadiness(tdId) {
  const td = await tdGet(tdId);
  if (!td) throw new Error('TD not found');
  const links = await tdLinks(tdId);
  const gaps = [];
  if (!links.some((l) => l.type === 'GSPR' && l.sectionId?.includes('ANNEX_II_D'))) gaps.push('Missing mandatory link: one GSPR link in section D');
  if (!links.some((l) => l.type === 'FMEA' && l.sectionId?.includes('ANNEX_II_E'))) gaps.push('Missing mandatory link: one FMEA link in section E');
  if (!links.some((l) => (l.type === 'Report' || l.type === 'Document') && (l.sectionId?.includes('ANNEX_III_G') || l.sectionId?.includes('ANNEX_III_H')))) {
    gaps.push('Missing mandatory link: one PMS plan/report link in section G or H');
  }
  const summary = await tdComputedSummary(td);
  return { readinessStatus: gaps.length ? 'Yellow' : summary.readinessStatus, complianceScore: summary.complianceScore, gaps };
}

function pdfBufferFromDoc(doc) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    doc.on('data', (chunk) => chunks.push(chunk));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
    doc.end();
  });
}

export async function tdNbExport(tdId) {
  const td = await tdGet(tdId);
  if (!td) throw new Error('TD not found');
  const sections = await tdSections(tdId);
  const links = await tdLinks(tdId);
  const summary = await tdComputedSummary(td);
  const sectionsDetailed = await Promise.all(sections.map(async (section) => ({
    section,
    content: await tdSectionContentBackfill(section.id),
    links: links.filter((l) => l.sectionId === section.id),
  })));

  const doc = new PDFDocument({ size: 'A4', margin: 42 });
  doc.fontSize(20).text('NB Package Summary', { align: 'center' });
  doc.moveDown();
  doc.fontSize(12).text(`TD: ${td.code} - ${td.title}`);
  doc.text(`Generated: ${new Date().toISOString()}`);
  doc.text(`Readiness: ${summary.readinessStatus}`);
  doc.text(`Compliance Score: ${summary.complianceScore}`);
  doc.text(`Manufacturer: DFS`);
  doc.addPage();
  doc.fontSize(16).text('Table of Contents');
  doc.moveDown(0.5);
  for (const section of sections) doc.fontSize(10).text(`${section.name} | ${section.status} | Updated ${section.lastUpdatedAt || '-'}`);
  for (const bundle of sectionsDetailed) {
    doc.addPage();
    doc.fontSize(14).text(bundle.section.name);
    doc.fontSize(10).text(`Status: ${bundle.section.status}`);
    doc.moveDown(0.5);
    doc.fontSize(11).text('Summary');
    doc.fontSize(10).text(bundle.content.summaryMarkdown || '-', { width: 500 });
    doc.moveDown(0.5);
    doc.fontSize(11).text('Structured Fields');
    const entries = Object.entries(bundle.content.contentJson || {});
    if (!entries.length) doc.fontSize(10).text('-');
    for (const [key, value] of entries) {
      const printable = Array.isArray(value) ? value.join(', ') : String(value ?? '');
      doc.fontSize(10).text(`${key}: ${printable}`);
    }
    doc.moveDown(0.5);
    doc.fontSize(11).text('Links');
    if (!bundle.links.length) doc.fontSize(10).text('-');
    for (const link of bundle.links) doc.fontSize(10).text(`${link.type} | ${link.label} | ${link.url || link.refId || '-'}`);
  }
  const pdfBuffer = await pdfBufferFromDoc(doc);

  const payload = {
    generatedAt: nowIso(),
    td,
    summary,
    toc: sections.map((s) => ({ id: s.id, templateKey: s.templateKey, name: s.name, status: s.status })),
    annexLinks: sections.map((s) => ({ sectionId: s.id, links: links.filter((l) => l.sectionId === s.id) })),
    appendices: {
      gspr: links.filter((l) => l.type === 'GSPR'),
      capa: links.filter((l) => l.type === 'CAPA'),
      risk: links.filter((l) => l.type === 'FMEA'),
    },
  };
  const exp = { id: cuid('tdexp'), tdId, status: 'completed', createdAt: nowIso(), payload, pdfBase64: pdfBuffer.toString('base64') };
  await putEntity(KEY_EXPORT, exp.id, exp, mem.exports, KEY_EXPORTS, mem.exportIds);
  return exp;
}

export async function tdExportGet(exportId) {
  return getEntity(KEY_EXPORT, exportId, mem.exports);
}
