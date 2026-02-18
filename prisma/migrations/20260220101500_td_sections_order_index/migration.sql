DO $$
BEGIN
  IF to_regclass('public.td_sections') IS NOT NULL THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_td_sections_td_id ON public.td_sections (td_id)';
    IF EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'td_sections' AND column_name = 'order_index'
    ) THEN
      EXECUTE 'CREATE INDEX IF NOT EXISTS idx_td_sections_td_id_order ON public.td_sections (td_id, order_index)';
    END IF;
  END IF;
END
$$;
