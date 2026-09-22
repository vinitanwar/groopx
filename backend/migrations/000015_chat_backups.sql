ALTER TYPE message_kind ADD VALUE IF NOT EXISTS 'location';

CREATE TABLE IF NOT EXISTS chat_backups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  payload JSONB NOT NULL,
  conversation_count INTEGER NOT NULL DEFAULT 0,
  message_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS chat_backups_user_created_idx
  ON chat_backups(user_id, created_at DESC);
