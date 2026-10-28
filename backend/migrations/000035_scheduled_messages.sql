CREATE TABLE IF NOT EXISTS scheduled_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  reply_to_id UUID REFERENCES messages(id) ON DELETE SET NULL,
  scheduled_at TIMESTAMPTZ NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'pending',
  sent_message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
  failure_reason VARCHAR(240),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  CHECK (LENGTH(BTRIM(body)) BETWEEN 1 AND 10000),
  CHECK (status IN ('pending', 'sent', 'cancelled', 'failed'))
);

CREATE INDEX IF NOT EXISTS scheduled_messages_due_idx
  ON scheduled_messages(scheduled_at, id) WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS scheduled_messages_sender_conversation_idx
  ON scheduled_messages(sender_id, conversation_id, scheduled_at DESC)
  WHERE status = 'pending';
