CREATE TABLE IF NOT EXISTS message_pins (
  message_id UUID PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  pinned_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS message_pins_conversation_created_idx
  ON message_pins(conversation_id, created_at DESC);
