DO $$
BEGIN
  IF to_regclass('public.td_sections') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_td_sections_td_id ON public.td_sections (td_id)';
  END IF;
  IF to_regclass('public.td_query_answers') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_td_query_answers_td_id_answered ON public.td_query_answers (td_id, answered)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_td_query_answers_td_id_answered_true ON public.td_query_answers (td_id) WHERE answered = true';
  END IF;
  IF to_regclass('public.td_links') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_td_links_td_id ON public.td_links (td_id)';
  END IF;

  IF to_regclass('public."TdSection"') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS "idx_TdSection_tdId_order" ON public."TdSection" ("tdId", "order")';
  END IF;
  IF to_regclass('public."TdQueryAnswer"') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS "idx_TdQueryAnswer_tdId_status" ON public."TdQueryAnswer" ("tdId", status)';
  END IF;
  IF to_regclass('public."TdArtifactLink"') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS "idx_TdArtifactLink_tdId" ON public."TdArtifactLink" ("tdId")';
  END IF;
END
$$;
