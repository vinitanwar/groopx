CREATE TYPE reminder_status AS ENUM ('upcoming', 'completed', 'cancelled');
CREATE TYPE call_kind AS ENUM ('audio', 'video');
CREATE TYPE call_status AS ENUM ('ringing', 'answered', 'missed', 'declined', 'ended');

CREATE TABLE reminders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
  title VARCHAR(160) NOT NULL,
  notes TEXT,
  scheduled_at TIMESTAMPTZ NOT NULL,
  status reminder_status NOT NULL DEFAULT 'upcoming',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE user_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform VARCHAR(20) NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
  push_token TEXT UNIQUE NOT NULL,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE calls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID REFERENCES conversations(id) ON DELETE SET NULL,
  initiated_by UUID REFERENCES users(id) ON DELETE SET NULL,
  room_name TEXT UNIQUE NOT NULL,
  kind call_kind NOT NULL,
  status call_status NOT NULL DEFAULT 'ringing',
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  answered_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ
);

CREATE TABLE call_participants (
  call_id UUID NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ,
  left_at TIMESTAMPTZ,
  PRIMARY KEY (call_id, user_id)
);

CREATE INDEX reminders_user_schedule_idx ON reminders(user_id, scheduled_at);
CREATE INDEX calls_conversation_started_idx ON calls(conversation_id, started_at DESC);
