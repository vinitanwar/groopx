ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS pinned_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS conversation_members_pinned_idx
  ON conversation_members(user_id, pinned_at DESC)
  WHERE pinned_at IS NOT NULL AND hidden_at IS NULL;
