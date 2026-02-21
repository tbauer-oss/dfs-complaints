DO $$
BEGIN
  IF to_regclass('public.td_sections') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_td_sections_td_id_section_key ON public.td_sections (td_id, section_id)';
  END IF;
  IF to_regclass('public.td_links') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_td_links_td_id_section ON public.td_links (td_id, section_id)';
  END IF;
  IF to_regclass('public.gspr_map') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_gspr_map_td_id_gspr_no ON public.gspr_map (td_id, gspr_no)';
  END IF;
  IF to_regclass('public.gspr_evidence') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_gspr_evidence_td_id_gspr_no ON public.gspr_evidence (td_id, gspr_no)';
  END IF;

  IF to_regclass('public."TdSection"') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS "idx_TdSection_tdId_id" ON public."TdSection" ("tdId", id)';
  END IF;
  IF to_regclass('public."TdArtifactLink"') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS "idx_TdArtifactLink_tdId_sectionId" ON public."TdArtifactLink" ("tdId", "sectionId")';
  END IF;
END
$$;
