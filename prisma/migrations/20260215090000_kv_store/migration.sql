CREATE TABLE IF NOT EXISTS kv_store (
  k text PRIMARY KEY,
  v jsonb NOT NULL,
  expires_at timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS kv_store_expires_at_idx ON kv_store (expires_at);
CREATE INDEX IF NOT EXISTS kv_store_key_prefix_idx ON kv_store ((left(k, 48)));

CREATE OR REPLACE FUNCTION set_kv_store_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_kv_store_updated_at ON kv_store;
CREATE TRIGGER trg_kv_store_updated_at
BEFORE UPDATE ON kv_store
FOR EACH ROW
EXECUTE FUNCTION set_kv_store_updated_at();
