ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS last_read_at TIMESTAMPTZ;

UPDATE conversation_members cm
SET last_read_at = m.created_at
FROM messages m
WHERE m.id = cm.last_read_message_id
  AND cm.last_read_at IS NULL;

CREATE INDEX IF NOT EXISTS conversation_members_unread_cursor_idx
  ON conversation_members(user_id, conversation_id, last_read_at);
