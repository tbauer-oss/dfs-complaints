import { query } from '../db.js';

export async function getLegalDocument(slug) {
  const { rows } = await query(`
    select d.*, v.version_label as current_version_label, v.consolidation_date as current_consolidation_date
    from legal_documents d
    left join legal_versions v on v.id = d.current_version_id
    where d.slug = $1
    limit 1
  `, [slug]);
  return rows[0] || null;
}

export async function listLegalDocuments() {
  const { rows } = await query(`
    select d.slug, d.title, d.celex, d.created_at, d.current_version_id,
           v.version_label as current_version_label, v.consolidation_date as current_consolidation_date, v.fetched_at as current_fetched_at
    from legal_documents d
    left join legal_versions v on v.id = d.current_version_id
    order by d.slug asc
  `);
  return rows;
}

export async function getSectionsForCurrentVersion(slug) {
  const { rows } = await query(`
    select s.*
    from legal_documents d
    join legal_sections s on s.version_id = d.current_version_id
    where d.slug = $1
    order by s.sort_order asc nulls last, s.section_key asc
  `, [slug]);
  return rows;
}

export async function getOutlineForCurrentVersion(slug) {
  const { rows } = await query(`
    select s.section_key, s.section_type, s.heading, s.sort_order
    from legal_documents d
    join legal_sections s on s.version_id = d.current_version_id
    where d.slug = $1
    order by s.sort_order asc nulls last, s.section_key asc
  `, [slug]);
  return rows;
}

export async function getSectionForCurrentVersion(slug, key) {
  const { rows } = await query(`
    select s.section_key, s.section_type, s.heading, s.sort_order, s.content_html, s.content_text, s.content_hash
    from legal_documents d
    join legal_sections s on s.version_id = d.current_version_id
    where d.slug = $1 and s.section_key = $2
    limit 1
  `, [slug, key]);
  return rows[0] || null;
}
