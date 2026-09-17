CREATE TYPE group_privacy AS ENUM ('private', 'public');

CREATE TABLE contacts (
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  contact_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  display_name VARCHAR(120) NOT NULL,
  phone VARCHAR(20),
  username VARCHAR(40),
  notes VARCHAR(100),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (owner_id, display_name)
);

ALTER TABLE conversations
  ADD COLUMN privacy group_privacy,
  ADD COLUMN description VARCHAR(200),
  ADD COLUMN deleted_at TIMESTAMPTZ;

CREATE TABLE media_objects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID REFERENCES users(id) ON DELETE SET NULL,
  object_key TEXT UNIQUE NOT NULL,
  file_name TEXT NOT NULL,
  content_type VARCHAR(120) NOT NULL,
  size_bytes BIGINT NOT NULL CHECK (size_bytes >= 0),
  width INTEGER,
  height INTEGER,
  duration_ms INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE message_attachments (
  message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  media_id UUID NOT NULL REFERENCES media_objects(id) ON DELETE CASCADE,
  sort_order SMALLINT NOT NULL DEFAULT 0,
  PRIMARY KEY (message_id, media_id)
);

CREATE INDEX contacts_owner_idx ON contacts(owner_id);
CREATE INDEX media_owner_idx ON media_objects(owner_id, created_at DESC);
