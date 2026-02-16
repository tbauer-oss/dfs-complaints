ALTER TABLE public.portal_users
  ADD COLUMN IF NOT EXISTS display_name text,
  ADD COLUMN IF NOT EXISTS is_sales boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_prrc boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS assigned_departments jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS tile_permissions jsonb NOT NULL DEFAULT '{}'::jsonb;
