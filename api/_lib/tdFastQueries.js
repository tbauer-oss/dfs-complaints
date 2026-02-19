import { queryWithStatementTimeout, safeQuery } from './db.js';
import { tdOverviewFast, tdSections, tdLinks } from './tdStore.js';

const TD_TABLES = [
  { td: 'td', sections: 'td_sections', answers: 'td_query_answers', links: 'td_links' },
  { td: '"TdFile"', sections: '"TdSection"', answers: '"TdQueryAnswer"', links: '"TdArtifactLink"' },
];

async function supportsTable(tableName) {
  const regclassName = tableName.includes('"') ? `public.${tableName}` : `public.${tableName}`;
  const probe = await safeQuery('SELECT to_regclass($1) AS name', [regclassName]);
  return probe.ok && probe.result?.rows?.[0]?.name;
}

async function firstWorkingLayout() {
  for (const layout of TD_TABLES) {
    if (await supportsTable(layout.td)) return layout;
  }
  return null;
}

export async function loadOverviewFromDb(tdId, timeoutMs = 4000, dbQuery = null) {
  const layout = await firstWorkingLayout();
  if (!layout) return null;

  const isCamel = layout.td.includes('"');
  const tdIdCol = isCamel ? '"tdId"' : 'td_id';
  const updatedCol = isCamel ? '"updatedAt"' : 'updated_at';
  const answeredCol = isCamel ? 'status IN (\'Complete\', \'NotApplicable\')' : 'answered = true';

  const tdSql = `SELECT id, title, status, ${updatedCol} AS updated_at FROM ${layout.td} WHERE id = $1 LIMIT 1`;
  const sectionsSql = `SELECT COUNT(*)::int AS count FROM ${layout.sections} WHERE ${tdIdCol} = $1`;
  const answersSql = `SELECT COUNT(*)::int AS count FROM ${layout.answers} WHERE ${tdIdCol} = $1 AND ${answeredCol}`;
  const linksSql = `SELECT COUNT(*)::int AS count FROM ${layout.links} WHERE ${tdIdCol} = $1`;

  const run = dbQuery || ((sql, params) => queryWithStatementTimeout(sql, params, timeoutMs));
  const [td, sec, ans, links] = await Promise.all([
    run(tdSql, [tdId]),
    run(sectionsSql, [tdId]),
    run(answersSql, [tdId]),
    run(linksSql, [tdId]),
  ]);

  const row = td.rows?.[0];
  if (!row) return null;
  return {
    id: row.id,
    title: row.title,
    status: row.status,
    updated_at: row.updated_at,
    section_count: sec.rows?.[0]?.count || 0,
    answered_count: ans.rows?.[0]?.count || 0,
    link_count: links.rows?.[0]?.count || 0,
  };
}

export async function loadOverviewFallback(tdId) {
  const lightweight = await tdOverviewFast(tdId);
  if (!lightweight) return null;
  return {
    id: tdId,
    title: null,
    status: null,
    updated_at: null,
    section_count: lightweight.section_count || 0,
    answered_count: lightweight.answered_count || 0,
    link_count: lightweight.link_count || 0,
  };
}

export async function loadSectionsMetaFromDb(tdId, limit, offset, timeoutMs = 4000, dbQuery = null) {
  const layout = await firstWorkingLayout();
  if (!layout) return null;
  const isCamel = layout.sections.includes('"');
  const sectionIdCol = isCamel ? 'id AS section_id' : 'section_id';
  const titleCol = isCamel ? 'name AS title' : 'title';
  const orderCol = isCamel ? '"order"' : '"order"';
  const updatedCol = isCamel ? '"lastUpdatedAt" AS updated_at' : 'updated_at';
  const tdIdCol = isCamel ? '"tdId"' : 'td_id';
  const templateCol = isCamel ? '"templateKey" AS template_key' : 'template_key';
  const statusCol = isCamel ? 'status' : 'status';

  const sql = `SELECT ${sectionIdCol}, ${titleCol}, ${orderCol} AS "order", ${updatedCol}, ${templateCol}, ${statusCol}
               FROM ${layout.sections}
               WHERE ${tdIdCol} = $1
               ORDER BY "order"
               LIMIT $2 OFFSET $3`;

  const countSql = `SELECT COUNT(*)::int AS count FROM ${layout.sections} WHERE ${tdIdCol} = $1`;

  const run = dbQuery || ((querySql, params) => queryWithStatementTimeout(querySql, params, timeoutMs));
  const [rowsRes, countRes] = await Promise.all([
    run(sql, [tdId, limit, offset]),
    run(countSql, [tdId]),
  ]);

  return {
    items: rowsRes.rows || [],
    total: countRes.rows?.[0]?.count || 0,
  };
}

export async function loadSectionsMetaFallback(tdId, limit, offset) {
  const sections = await tdSections(tdId);
  const links = await tdLinks(tdId);
  const paged = sections.slice(offset, offset + limit).map((section) => {
    return {
      section_id: section.id,
      title: section.name,
      order: section.order,
      updated_at: section.lastUpdatedAt || null,
      template_key: section.templateKey,
      status: section.status,
      link_count: links.filter((l) => l.sectionId === section.id).length,
    };
  });

  return { items: paged, total: sections.length };
}
