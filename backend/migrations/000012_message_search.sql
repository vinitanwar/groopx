CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS messages_body_trgm_idx
  ON messages USING GIN (body gin_trgm_ops)
  WHERE deleted_at IS NULL;

