CREATE TYPE conversation_kind AS ENUM ('direct', 'group', 'community');
CREATE TYPE message_kind AS ENUM ('text', 'image', 'video', 'audio', 'file', 'call', 'system');
CREATE TYPE message_status AS ENUM ('sent', 'delivered', 'read');

CREATE TABLE conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kind conversation_kind NOT NULL,
  title VARCHAR(160),
  avatar_url TEXT,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  last_message_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE conversation_members (
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role VARCHAR(30) NOT NULL DEFAULT 'member',
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  archived_at TIMESTAMPTZ,
  muted_until TIMESTAMPTZ,
  last_read_message_id UUID,
  PRIMARY KEY (conversation_id, user_id)
);

CREATE TABLE messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES users(id) ON DELETE SET NULL,
  kind message_kind NOT NULL DEFAULT 'text',
  body TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  reply_to_id UUID REFERENCES messages(id) ON DELETE SET NULL,
  status message_status NOT NULL DEFAULT 'sent',
  edited_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE conversation_members
  ADD CONSTRAINT conversation_members_last_read_fk
  FOREIGN KEY (last_read_message_id) REFERENCES messages(id) ON DELETE SET NULL;

CREATE TABLE message_reactions (
  message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  emoji VARCHAR(16) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (message_id, user_id, emoji)
);

CREATE INDEX messages_conversation_created_idx ON messages(conversation_id, created_at DESC);
CREATE INDEX conversation_members_user_idx ON conversation_members(user_id, archived_at);
