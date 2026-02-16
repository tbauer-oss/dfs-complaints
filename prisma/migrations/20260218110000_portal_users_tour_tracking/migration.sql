ALTER TABLE public.portal_users
  ADD COLUMN IF NOT EXISTS tour_seen boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS tour_seen_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS tour_version integer NOT NULL DEFAULT 1;
