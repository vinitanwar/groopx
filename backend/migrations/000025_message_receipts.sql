CREATE TABLE IF NOT EXISTS message_receipts (
  message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  delivered_at TIMESTAMPTZ,
  read_at TIMESTAMPTZ,
  PRIMARY KEY (message_id, user_id)
);

CREATE INDEX IF NOT EXISTS message_receipts_user_pending_idx
  ON message_receipts(user_id, message_id) WHERE read_at IS NULL;

CREATE OR REPLACE FUNCTION create_message_receipts() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO message_receipts(message_id,user_id)
  SELECT NEW.id,cm.user_id FROM conversation_members cm
  WHERE cm.conversation_id=NEW.conversation_id AND cm.user_id<>NEW.sender_id
  ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS messages_create_receipts ON messages;
CREATE TRIGGER messages_create_receipts AFTER INSERT ON messages
FOR EACH ROW EXECUTE FUNCTION create_message_receipts();

INSERT INTO message_receipts(message_id,user_id,delivered_at,read_at)
SELECT m.id,cm.user_id,
  CASE WHEN m.status IN ('delivered','read') THEN m.created_at END,
  CASE WHEN u.read_receipts AND cm.last_read_at>=m.created_at THEN cm.last_read_at END
FROM messages m
JOIN conversation_members cm ON cm.conversation_id=m.conversation_id AND cm.user_id<>m.sender_id
JOIN users u ON u.id=cm.user_id
ON CONFLICT DO NOTHING;
