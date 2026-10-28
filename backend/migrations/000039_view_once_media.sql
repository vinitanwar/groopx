ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS view_once BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS view_once_opens (
  message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (message_id, user_id)
);

CREATE INDEX IF NOT EXISTS view_once_opens_user_idx
  ON view_once_opens(user_id, opened_at DESC);

CREATE INDEX IF NOT EXISTS message_attachments_media_idx
  ON message_attachments(media_id);
