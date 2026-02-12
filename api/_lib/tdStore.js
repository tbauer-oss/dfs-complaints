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
const KEY_QUERY_ANSWERS = `${PREFIX}query-answers`;
const KEY_QUERY_LINKS = `${PREFIX}query-links`;
const KEY = (id) => `${PREFIX}file:${id}`;
const KEY_SECTION = (id) => `${PREFIX}section:${id}`;
const KEY_LINK = (id) => `${PREFIX}link:${id}`;
const KEY_CHANGE = (id) => `${PREFIX}change:${id}`;
const KEY_IMPACT = (id) => `${PREFIX}impact:${id}`;
const KEY_EXPORT = (id) => `${PREFIX}export:${id}`;
const KEY_QUERY_ANSWER = (id) => `${PREFIX}query-answer:${id}`;
const KEY_QUERY_LINK = (id) => `${PREFIX}query-link:${id}`;
const KEY_CONTENT = `${PREFIX}section-content`;
const KEY_SECTION_CONTENT = (id) => `${PREFIX}section-content:${id}`;

const lifecycleStates = new Set(['Development', 'Released', 'PostMarket', 'Update', 'Sunset', 'Obsolete']);
const tdStatus = new Set(['Green', 'Yellow', 'Red', 'Draft']);
const sectionStatus = new Set(['NotStarted', 'InProgress', 'Complete', 'Blocked', 'NotApplicable']);
const linkTypes = new Set(['Document', 'GSPR', 'FMEA', 'CAPA', 'ComplaintMetric', 'Supplier', 'Training', 'ExternalLink', 'Report', 'Change']);
const queryStatuses = new Set(['NotStarted', 'InProgress', 'Complete', 'Blocked', 'NotApplicable']);
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
  queryAnswerIds: new Set(),
  queryLinkIds: new Set(),
  sectionContentIds: new Set(),
  files: new Map(),
  sections: new Map(),
  links: new Map(),
  changes: new Map(),
  impacts: new Map(),
  exports: new Map(),
  queryAnswers: new Map(),
  queryLinks: new Map(),
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

export const TD_QUERY_TEMPLATES = [
  ['ANNEX_II_A_1','ANNEX_II_A','Intended purpose and clinical benefit','Define intended purpose and expected clinical benefit; align claims with clinical evidence and linked GSPR requirements.',10,['GSPR','Report','Document'], 'PRRC',['Annex II','Device description','Clinical']],
  ['ANNEX_II_A_2','ANNEX_II_A','Device description, materials, variants','Describe materials, geometry, variants and accessories with links to technical drawings/specifications and risk-relevant characteristics.',20,['Document','FMEA','Supplier'],'QMB',['Annex II','Device description','Variants']],
  ['ANNEX_II_A_3','ANNEX_II_A','UDI-DI and Basic UDI-DI mapping','Document UDI-DI / Basic UDI-DI strategy and traceability to labels/IFU versions.',30,['Document'],'RA',['Annex II','UDI']],
  ['ANNEX_II_A_4','ANNEX_II_A','Classification and rule justification','Document MDR class and applied classification rule rationale with justification references.',40,['GSPR','Document'],'RA',['Annex II','Classification']],
  ['ANNEX_II_A_5','ANNEX_II_A','Principle of operation and performance claims','Describe operating principle and key performance claims with validation references.',50,['Report','GSPR','Document'],'R&D',['Annex II','Performance']],
  ['ANNEX_II_A_6','ANNEX_II_A','Previous generations / similar devices','Reference previous generations or similar devices and summarize relevance to current benefit-risk.',60,['Report','Document'],'Clinical',['Annex II','State of the art']],
  ['ANNEX_II_B_1','ANNEX_II_B','Label content completeness','Confirm label content covers symbols, warnings, UDI, manufacturer and legal data for intended markets.',10,['Document'],'RA',['Annex II','Labeling']],
  ['ANNEX_II_B_2','ANNEX_II_B','IFU completeness and reprocessing content','Confirm IFU includes intended use, contraindications, warnings and reprocessing instructions where relevant.',20,['Document','Report'],'RA',['Annex II','IFU']],
  ['ANNEX_II_B_3','ANNEX_II_B','Language and translation control','Document language variants, translation workflow and approval controls.',30,['Document','Change'],'QMS',['Annex II','Translation']],
  ['ANNEX_II_B_4','ANNEX_II_B','Traceability of label/IFU revisions','Show synchronization between label/IFU revisions and TD/Change Control updates.',40,['Change','Document'],'QMS',['Annex II','Traceability']],
  ['ANNEX_II_B_5','ANNEX_II_B','User training and communication','Define user training needs, communication channels and associated records.',50,['Training','Document'],'Training',['Annex II','Training']],
  ['ANNEX_II_C_1','ANNEX_II_C','Manufacturing process overview','Provide high-level process map and site responsibilities for manufacturing and release.',10,['Supplier','Document'],'Operations',['Annex II','Manufacturing']],
  ['ANNEX_II_C_2','ANNEX_II_C','Critical process parameters and controls','Define critical process parameters, controls, limits and monitoring approach.',20,['FMEA','CAPA','Document'],'Operations',['Annex II','Process control']],
  ['ANNEX_II_C_3','ANNEX_II_C','Outsourced processes and controls','Describe outsourced activities and qualification/audit controls for external partners.',30,['Supplier','Document'],'Supplier',['Annex II','Supplier']],
  ['ANNEX_II_C_4','ANNEX_II_C','Acceptance criteria and inspection plans','Document incoming/in-process/final acceptance criteria and inspection sampling plans.',40,['Document','Report'],'Quality',['Annex II','Inspection']],
  ['ANNEX_II_C_5','ANNEX_II_C','Change management and design transfer','Explain design transfer controls and linkage to formal change management.',50,['Change','Document'],'QMS',['Annex II','Change control']],
  ['ANNEX_II_D_1','ANNEX_II_D','GSPR completeness and open gaps','Assess current GSPR completion level and list unresolved requirements/actions.',10,['GSPR','CAPA'],'RA',['Annex II','GSPR']],
  ['ANNEX_II_D_2','ANNEX_II_D','Claims-to-evidence traceability','Ensure major claims have traceable evidence links (verification, clinical, PMS).',20,['GSPR','Report','Document'],'RA',['Annex II','Traceability']],
  ['ANNEX_II_D_3','ANNEX_II_D','Partial/non-fulfilled requirements','Document non-fulfilled or partial requirements and linked remediation actions.',30,['CAPA','GSPR','Change'],'QMB',['Annex II','CAPA']],
  ['ANNEX_II_E_1','ANNEX_II_E','Risk management file completeness','Confirm risk management file is complete and up to date for current design state.',10,['FMEA','Document'],'Risk',['Annex II','Risk']],
  ['ANNEX_II_E_2','ANNEX_II_E','Benefit-risk conclusion justification','Document rationale for benefit-risk conclusion using clinical and PMS evidence.',20,['Report','Document'],'Clinical',['Annex II','Benefit-risk']],
  ['ANNEX_II_E_3','ANNEX_II_E','Residual risks and IFU communication','Confirm residual risks are acceptable and communicated through IFU/label where needed.',30,['FMEA','Document','GSPR'],'Risk',['Annex II','Residual risk']],
  ['ANNEX_II_E_4','ANNEX_II_E','Post-market risk feedback loop','Show how post-market signals feed back into risk management and CAPA.',40,['CAPA','Report','FMEA'],'PMS',['Annex II','PMS']],
  ['ANNEX_II_F_1','ANNEX_II_F','Applied standards and common specs','List applicable standards/common specifications and current conformity evidence.',10,['Document','Report'],'RA',['Annex II','Standards']],
  ['ANNEX_II_F_2','ANNEX_II_F','Biocompatibility / chemical characterization','Summarize biocompatibility and chemistry evidence as applicable to patient contact.',20,['Report'],'R&D',['Annex II','Biocompatibility']],
  ['ANNEX_II_F_3','ANNEX_II_F','Reprocessing validation','Provide cleaning/disinfection/sterilization validation status and key references.',30,['Report','Document'],'Validation',['Annex II','Reprocessing']],
  ['ANNEX_II_F_4','ANNEX_II_F','Performance testing evidence','Summarize bench/performance tests supporting intended performance.',40,['Report'],'Validation',['Annex II','Performance']],
  ['ANNEX_II_F_5','ANNEX_II_F','Packaging validation','Summarize packaging integrity/shelf-life/transport validation evidence.',50,['Report','Document'],'Validation',['Annex II','Packaging']],
  ['ANNEX_II_F_6','ANNEX_II_F','Software validation (if applicable)','Provide software lifecycle and validation evidence, or justify non-applicability.',60,['Report','Document'],'Software',['Annex II','Software']],
  ['ANNEX_III_G_1','ANNEX_III_G','PMS plan scope and responsibilities','Document PMS plan ownership, scope and responsibilities.',10,['Document'],'PMS',['Annex III','PMS']],
  ['ANNEX_III_G_2','ANNEX_III_G','PMS data sources','List PMS data sources (complaints, trends, literature, supplier feedback).',20,['Report','Supplier','ComplaintMetric'],'PMS',['Annex III','Data sources']],
  ['ANNEX_III_G_3','ANNEX_III_G','Signals, thresholds and triggers','Define surveillance thresholds/signals and escalation triggers to CAPA/change/vigilance.',30,['CAPA','Change','Report'],'PMS',['Annex III','Signals']],
  ['ANNEX_III_G_4','ANNEX_III_G','PMCF plan applicability','Describe PMCF plan and rationale if required; otherwise justify non-applicability.',40,['Report','Document'],'Clinical',['Annex III','PMCF']],
  ['ANNEX_III_H_1','ANNEX_III_H','Applicable report type and rationale','Define whether PMS report or PSUR applies and provide rationale.',10,['Document'],'RA',['Annex III','PSUR']],
  ['ANNEX_III_H_2','ANNEX_III_H','Reporting period and key findings','Capture reporting period coverage and key post-market findings.',20,['Report'],'PMS',['Annex III','Findings']],
  ['ANNEX_III_H_3','ANNEX_III_H','Trend analysis and complaint linkage','Summarize trends and link complaint metrics relevant for risk/performance changes.',30,['ComplaintMetric','Report'],'PMS',['Annex III','Complaints']],
  ['ANNEX_III_H_4','ANNEX_III_H','Actions taken and linkage','Document resulting actions and linkage to CAPA/change records.',40,['CAPA','Change'],'QMS',['Annex III','Actions']],
  ['ANNEX_III_H_5','ANNEX_III_H','Conclusions on benefit-risk and GSPR','State impact on benefit-risk profile and GSPR conformity.',50,['GSPR','Report'],'PRRC',['Annex III','Conclusion']],
].map(([templateKey, sectionTemplateKey, title, description, order, suggestedLinkTypes, defaultOwnersRole, tags]) => ({
  id: `tpl_${templateKey.toLowerCase()}`,
  templateKey,
  sectionTemplateKey,
  title,
  description,
  order,
  mandatory: true,
  suggestedLinkTypes,
  defaultOwnersRole,
  tags,
}));

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
  const byCode = new Map(existing.map((entry) => [String(entry?.code || '').toUpperCase(), entry]));
  let createdAny = false;
  const catalog = await getUniqueMdrTdEntries().catch(() => []);
  for (const entry of catalog) {
    const code = String(entry?.code || '').trim().toUpperCase();
    if (!/^MDR-TD\d+$/i.test(code)) continue;

    const canonicalTitle = String(entry?.title || entry?.label || code).trim() || code;
    const existingEntry = byCode.get(code);

    if (existingEntry) {
      const existingTitle = String(existingEntry?.title || '').trim();
      const hasBrokenReplacementChar = existingTitle.includes('�');
      if (hasBrokenReplacementChar && existingTitle !== canonicalTitle) {
        const next = normalizeFile({
          ...existingEntry,
          title: canonicalTitle,
          productGroup: entry?.productGroup || existingEntry.productGroup || null,
          classification: entry?.classification || existingEntry.classification || null,
          rule: entry?.rule || existingEntry.rule || null,
          id: existingEntry.id,
          code: existingEntry.code,
          createdAt: existingEntry.createdAt,
        }, existingEntry.ownerUserId || null);
        await putEntity(KEY, next.id, next, mem.files, KEY_ALL, mem.ids);
      }
      continue;
    }

    const seeded = normalizeFile({
      id: deterministicTdId(code),
      code,
      title: canonicalTitle,
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
    byCode.set(code, seeded);
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



function normalizeQueryStatus(status) {
  return queryStatuses.has(status) ? status : 'NotStarted';
}

function queryTemplatesBySection(templateKey) {
  return TD_QUERY_TEMPLATES.filter((item) => item.sectionTemplateKey === templateKey).sort((a, b) => a.order - b.order);
}

async function tdQueryAnswersRaw(tdId) {
  const ids = await withStore((r)=>r.smembers(KEY_QUERY_ANSWERS), ()=>Array.from(mem.queryAnswerIds));
  const items = [];
  for (const id of ids) {
    const answer = await getEntity(KEY_QUERY_ANSWER, id, mem.queryAnswers);
    if (answer?.tdId === tdId) items.push(answer);
  }
  return items;
}

function buildQueryAnswer(section, template, actorUserId = null) {
  return {
    id: cuid('tdqa'),
    tdId: section.tdId,
    sectionId: section.id,
    templateKey: template.templateKey,
    status: 'NotStarted',
    answerMarkdown: '',
    rationaleMarkdown: '',
    ownerUserId: section.ownerUserId || null,
    dueAt: null,
    reviewCadenceDays: 180,
    evidenceJson: { documentRefs: [], standardRefs: [], reportRefs: [] },
    updatedAt: nowIso(),
    updatedByUserId: actorUserId || null,
  };
}

export async function tdBootstrapQueries(tdId, actorUserId = null) {
  const sections = await tdSections(tdId);
  const existing = await tdQueryAnswersRaw(tdId);
  const byKey = new Set(existing.map((item) => `${item.sectionId}:${item.templateKey}`));
  const created = [];
  for (const section of sections) {
    for (const template of queryTemplatesBySection(section.templateKey)) {
      const k = `${section.id}:${template.templateKey}`;
      if (byKey.has(k)) continue;
      const answer = buildQueryAnswer(section, template, actorUserId);
      await putEntity(KEY_QUERY_ANSWER, answer.id, answer, mem.queryAnswers, KEY_QUERY_ANSWERS, mem.queryAnswerIds);
      created.push(answer);
    }
  }
  return { createdCount: created.length, created };
}

export async function tdQueries(tdId, sectionId = null) {
  await tdBootstrapQueries(tdId);
  const answers = await tdQueryAnswersRaw(tdId);
  const queryLinks = await tdQueryLinksByTd(tdId);
  return answers
    .filter((item) => (sectionId ? item.sectionId === sectionId : true))
    .map((answer) => {
      const template = TD_QUERY_TEMPLATES.find((tpl) => tpl.templateKey === answer.templateKey) || null;
      return {
        ...answer,
        template,
        links: queryLinks.filter((link) => link.answerId === answer.id),
      };
    })
    .sort((a, b) => {
      if (a.template?.order && b.template?.order) return a.template.order - b.template.order;
      return a.templateKey.localeCompare(b.templateKey);
    });
}

export async function tdQueryUpdate(answerId, payload, actorUserId = null) {
  const current = await getEntity(KEY_QUERY_ANSWER, answerId, mem.queryAnswers);
  if (!current) throw new Error('query answer not found');
  const next = {
    ...current,
    status: normalizeQueryStatus(payload?.status ?? current.status),
    answerMarkdown: payload?.answerMarkdown === undefined ? current.answerMarkdown : String(payload.answerMarkdown || ''),
    rationaleMarkdown: payload?.rationaleMarkdown === undefined ? current.rationaleMarkdown : String(payload.rationaleMarkdown || ''),
    ownerUserId: payload?.ownerUserId === undefined ? current.ownerUserId : (payload.ownerUserId ? String(payload.ownerUserId) : null),
    dueAt: payload?.dueAt === undefined ? current.dueAt : (payload.dueAt ? String(payload.dueAt) : null),
    reviewCadenceDays: payload?.reviewCadenceDays === undefined ? current.reviewCadenceDays : Number(payload.reviewCadenceDays) || current.reviewCadenceDays,
    evidenceJson: payload?.evidenceJson === undefined ? current.evidenceJson : payload.evidenceJson,
    updatedAt: nowIso(),
    updatedByUserId: actorUserId || current.updatedByUserId || null,
  };
  await putEntity(KEY_QUERY_ANSWER, answerId, next, mem.queryAnswers, KEY_QUERY_ANSWERS, mem.queryAnswerIds);
  return next;
}

export async function tdQueryLinksByTd(tdId) {
  const ids = await withStore((r)=>r.smembers(KEY_QUERY_LINKS), ()=>Array.from(mem.queryLinkIds));
  const items = [];
  const answers = await tdQueryAnswersRaw(tdId);
  const answerIds = new Set(answers.map((a) => a.id));
  for (const id of ids) {
    const link = await getEntity(KEY_QUERY_LINK, id, mem.queryLinks);
    if (link && answerIds.has(link.answerId)) items.push(link);
  }
  return items;
}

export async function tdQueryLinkCreate(answerId, payload) {
  const answer = await getEntity(KEY_QUERY_ANSWER, answerId, mem.queryAnswers);
  if (!answer) throw new Error('query answer not found');
  const item = {
    id: cuid('tdql'),
    answerId,
    type: linkTypes.has(payload?.type) ? payload.type : 'Document',
    refId: String(payload?.refId || '').trim(),
    label: String(payload?.label || '').trim(),
    url: payload?.url ? String(payload.url) : null,
    metaJson: payload?.metaJson || null,
    createdAt: nowIso(),
  };
  if (!item.label) throw new Error('label is required');
  await putEntity(KEY_QUERY_LINK, item.id, item, mem.queryLinks, KEY_QUERY_LINKS, mem.queryLinkIds);
  return item;
}

export async function tdQueryLinkDelete(linkId) {
  const current = await getEntity(KEY_QUERY_LINK, linkId, mem.queryLinks);
  if (!current) throw new Error('query link not found');
  return withStore(
    async (r) => {
      await r.del(KEY_QUERY_LINK(linkId));
      await r.srem(KEY_QUERY_LINKS, linkId);
      return current;
    },
    () => {
      mem.queryLinks.delete(linkId);
      mem.queryLinkIds.delete(linkId);
      return current;
    },
  );
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
  const sections = await tdSections(tdId);
  const links = await tdLinks(tdId);
  const queries = await tdQueries(tdId);
  const gaps = [];
  const now = Date.now();

  const mandatoryBySection = {
    ANNEX_II_D: ['GSPR'],
    ANNEX_II_E: ['FMEA'],
    ANNEX_III_G: ['Report', 'Document'],
    ANNEX_III_H: ['Report', 'Document'],
  };

  const sectionStats = sections.map((section) => {
    const sectionQueries = queries.filter((q) => q.sectionId === section.id);
    const complete = sectionQueries.filter((q) => q.status === 'Complete' || q.status === 'NotApplicable').length;
    const total = sectionQueries.length;
    const completion = total ? Math.round((complete / total) * 100) : 0;
    const mandatoryOpen = sectionQueries.filter((q) => q.template?.mandatory !== false && !['Complete', 'NotApplicable'].includes(q.status));
    const overdue = sectionQueries.filter((q) => q.template?.mandatory !== false && q.dueAt && Date.parse(q.dueAt) < now && !['Complete', 'NotApplicable'].includes(q.status));
    const requiredTypes = mandatoryBySection[section.templateKey] || [];
    const missingLinkTypes = requiredTypes.filter((type) => !links.some((l) => l.sectionId === section.id && (type === 'Document' ? ['Document', 'Report'].includes(l.type) : l.type === type)));
    if (mandatoryOpen.length) gaps.push(`${section.templateKey}: mandatory queries open (${mandatoryOpen.length})`);
    if (overdue.length) gaps.push(`${section.templateKey}: overdue mandatory queries (${overdue.length})`);
    for (const type of missingLinkTypes) gaps.push(`${section.templateKey}: missing mandatory link ${type}`);
    return { sectionId: section.id, templateKey: section.templateKey, completion, totalQueries: total, completeQueries: complete, mandatoryOpenCount: mandatoryOpen.length, overdueCount: overdue.length, missingLinkTypes };
  });

  const summary = await tdComputedSummary(td);
  const readinessStatus = gaps.length ? (gaps.some((g) => g.includes('overdue')) ? 'Red' : 'Yellow') : summary.readinessStatus;
  return { readinessStatus, complianceScore: summary.complianceScore, gaps, sections: sectionStats };
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
