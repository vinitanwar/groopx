ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS favorite BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS conversation_members_favorite_idx
  ON conversation_members(user_id, favorite) WHERE favorite=TRUE AND hidden_at IS NULL;
