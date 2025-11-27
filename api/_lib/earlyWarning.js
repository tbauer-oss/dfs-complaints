// api/_lib/earlyWarning.js
// Build early warning insights for representatives based on recent complaint trends.

import { getProductIndex, normalizeArticleNumber } from './products.js';

const DAY_MS = 24 * 60 * 60 * 1000;
const DEFAULT_WINDOW_DAYS = Math.max(1, Number(process.env.EARLY_WARNING_WINDOW_DAYS || 90));
const DEFAULT_COMPARE_DAYS = Math.max(1, Number(process.env.EARLY_WARNING_COMPARE_DAYS || 90));

const ARTICLE_KEYS = [
  'article',
  'article_no',
  'articleNo',
  'articleNumber',
  'article_name',
  'product',
  'productName',
  'artikel',
  'artikelnummer',
];

const CUSTOMER_KEYS = [
  'customerEmail',
  'email',
  'customer',
  'mail',
  'customer_email',
  'customerMail',
  'userEmail',
];

function norm(value) {
  return (value ?? '').toString().trim();
}

function normLower(value) {
  return norm(value).toLowerCase();
}

function pickValue(source, keys) {
  if (!source || typeof source !== 'object') return '';
  for (const key of keys) {
    if (!Object.prototype.hasOwnProperty.call(source, key)) continue;
    const val = norm(source[key]);
    if (val) return val;
  }
  return '';
}

function extractArticle(complaint) {
  const payload = complaint?.payload || {};
  const product = payload?.product || {};
  const sources = [complaint, payload, product];
  for (const source of sources) {
    const v = pickValue(source, ARTICLE_KEYS);
    if (v) return normalizeArticleNumber(v);
  }
  return '';
}

function extractCustomer(complaint) {
  const payload = complaint?.payload || {};
  const account = complaint?.account || {};
  const customer = complaint?.customer || {};
  const user = complaint?.user || {};
  const sources = [complaint, payload, account, customer, user, payload?.customer, payload?.account];
  for (const src of sources) {
    const v = pickValue(src, CUSTOMER_KEYS);
    if (v) return normLower(v);
  }
  return '';
}

function pickTimestamp(complaint) {
  const candidates = [
    complaint?.updatedAt,
    complaint?.createdAt,
    complaint?.created,
    complaint?.payload?.createdAt,
    complaint?.payload?.submittedAt,
  ];
  for (const candidate of candidates) {
    if (candidate === null || candidate === undefined) continue;
    const n = Number(candidate);
    if (Number.isNaN(n) || n <= 0) continue;
    if (n < 10_000_000_000) return n * 1000; // seconds
    return n; // already ms
  }
  return null;
}

function classifyTrend(prev, recent) {
  if (recent <= 0) return null;
  const increase = recent - prev;
  const pct = prev > 0 ? increase / prev : Infinity;

  if (recent >= 3 && (pct === Infinity || pct >= 1.5)) {
    return { level: 'critical', pct };
  }
  if (recent >= 2 && (pct === Infinity || pct >= 0.5)) {
    return { level: 'warn', pct };
  }
  if (recent > prev && recent >= 2) {
    return { level: 'info', pct };
  }
  return null;
}

function buildDescription(label, prev, recent) {
  const diff = recent - prev;
  if (prev <= 0) return `${label}: ${recent} Reklamationen (vorher keine)`;
  const pct = Math.round((diff / prev) * 100);
  return `${label}: +${pct}% (${recent} vs. ${prev})`;
}

export async function buildEarlyWarnings(complaints, options = {}) {
  const windowDays = Number(options.windowDays || DEFAULT_WINDOW_DAYS);
  const compareDays = Number(options.compareDays || DEFAULT_COMPARE_DAYS);
  const now = Date.now();
  const recentStart = now - windowDays * DAY_MS;
  const compareStart = recentStart - compareDays * DAY_MS;
  const productIndex = options.productIndex || (await getProductIndex());

  const articleStats = new Map();
  const customerStats = new Map();
  const groupStats = new Map();

  const relevantComplaints = (Array.isArray(complaints) ? complaints : []).filter((c) => {
    const ts = pickTimestamp(c);
    return ts && ts >= compareStart;
  });

  for (const c of relevantComplaints) {
    const ts = pickTimestamp(c);
    if (!ts) continue;
    const article = extractArticle(c);
    const customer = extractCustomer(c);
    const product = productIndex.get(article) || null;
    const group = product?.productGroup || '';
    const periodKey = ts >= recentStart ? 'recent' : 'previous';

    if (article) {
      const entry = articleStats.get(article) || { recent: 0, previous: 0, product, article };
      entry[periodKey] += 1;
      articleStats.set(article, entry);
    }

    if (group) {
      const entry = groupStats.get(group) || { recent: 0, previous: 0, group };
      entry[periodKey] += 1;
      groupStats.set(group, entry);
    }

    if (customer) {
      const entry = customerStats.get(customer) || { recent: 0, previous: 0, groups: new Map(), customer };
      entry[periodKey] += 1;
      if (group) {
        entry.groups.set(group, (entry.groups.get(group) || 0) + 1);
      }
      customerStats.set(customer, entry);
    }
  }

  const warnings = [];

  for (const entry of articleStats.values()) {
    const trend = classifyTrend(entry.previous, entry.recent);
    if (!trend) continue;
    const group = entry.product?.productGroup || '';
    const productName = entry.product?.productName || '';
    const title = `Achtung – steigende Reklamationen für Artikel ${entry.article}`;
    const description = buildDescription(group || productName || 'Artikel', entry.previous, entry.recent);

    warnings.push({
      id: `article-${entry.article}`,
      type: 'article',
      level: trend.level,
      title,
      description,
      articleNumber: entry.article,
      articleNumbers: [entry.article],
      productGroup: group,
      productName,
      recentCount: entry.recent,
      previousCount: entry.previous,
      changePercent: trend.pct === Infinity ? null : trend.pct,
      links: {
        products: { articleNumbers: [entry.article], productGroup: group },
        complaints: { articleNumbers: [entry.article] },
      },
    });
  }

  for (const entry of customerStats.values()) {
    const trend = classifyTrend(entry.previous, entry.recent);
    if (!trend) continue;
    let topGroup = '';
    let topCount = 0;
    for (const [g, cnt] of entry.groups.entries()) {
      if (cnt > topCount) {
        topGroup = g;
        topCount = cnt;
      }
    }
    const title = `Achtung – steigende Reklamationen für Kunde ${entry.customer}`;
    const label = topGroup ? `Kunde ${entry.customer} in ${topGroup}` : `Kunde ${entry.customer}`;
    const description = buildDescription(label, entry.previous, entry.recent);

    warnings.push({
      id: `customer-${entry.customer}`,
      type: 'customer',
      level: trend.level,
      title,
      description,
      customerEmail: entry.customer,
      productGroup: topGroup,
      recentCount: entry.recent,
      previousCount: entry.previous,
      changePercent: trend.pct === Infinity ? null : trend.pct,
      articleNumbers: [],
      links: {
        products: { articleNumbers: [], productGroup: topGroup },
        complaints: { customerEmail: entry.customer },
      },
    });
  }

  for (const entry of groupStats.values()) {
    const trend = classifyTrend(entry.previous, entry.recent);
    if (!trend) continue;
    const title = `Achtung – steigende Reklamationen in Produktgruppe ${entry.group}`;
    const description = buildDescription(`Produktgruppe ${entry.group}`, entry.previous, entry.recent);

    warnings.push({
      id: `group-${entry.group}`,
      type: 'productGroup',
      level: trend.level,
      title,
      description,
      productGroup: entry.group,
      recentCount: entry.recent,
      previousCount: entry.previous,
      changePercent: trend.pct === Infinity ? null : trend.pct,
      articleNumbers: [],
      links: {
        products: { articleNumbers: [], productGroup: entry.group },
        complaints: { productGroup: entry.group },
      },
    });
  }

  warnings.sort((a, b) => {
    const order = { critical: 0, warn: 1, info: 2 };
    const la = order[a.level] ?? 3;
    const lb = order[b.level] ?? 3;
    if (la !== lb) return la - lb;
    return (b.recentCount || 0) - (a.recentCount || 0);
  });

  return {
    generatedAt: now,
    windowDays,
    compareDays,
    items: warnings,
  };
}

