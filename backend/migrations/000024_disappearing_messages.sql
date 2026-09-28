ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS disappearing_seconds INTEGER NOT NULL DEFAULT 0;

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS messages_expiry_idx
  ON messages(expires_at) WHERE expires_at IS NOT NULL AND deleted_at IS NULL;

CREATE OR REPLACE FUNCTION set_message_expiry() RETURNS TRIGGER AS $$
DECLARE lifetime INTEGER;
BEGIN
  SELECT disappearing_seconds INTO lifetime FROM conversations WHERE id=NEW.conversation_id;
  IF lifetime > 0 THEN NEW.expires_at := NOW() + make_interval(secs => lifetime); END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS messages_set_expiry ON messages;
CREATE TRIGGER messages_set_expiry BEFORE INSERT ON messages
FOR EACH ROW EXECUTE FUNCTION set_message_expiry();
