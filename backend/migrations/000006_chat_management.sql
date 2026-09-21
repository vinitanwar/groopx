ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS conversation_members_visible_idx
  ON conversation_members(user_id, archived_at, hidden_at);
