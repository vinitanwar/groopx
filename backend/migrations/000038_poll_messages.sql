ALTER TYPE message_kind ADD VALUE IF NOT EXISTS 'poll';

CREATE TABLE IF NOT EXISTS message_polls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL UNIQUE REFERENCES messages(id) ON DELETE CASCADE,
  question VARCHAR(300) NOT NULL,
  allow_multiple BOOLEAN NOT NULL DEFAULT FALSE,
  closed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS poll_options (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id UUID NOT NULL REFERENCES message_polls(id) ON DELETE CASCADE,
  position SMALLINT NOT NULL CHECK (position BETWEEN 0 AND 11),
  label VARCHAR(120) NOT NULL,
  UNIQUE (poll_id, position),
  UNIQUE (poll_id, id)
);

CREATE TABLE IF NOT EXISTS poll_votes (
  poll_id UUID NOT NULL REFERENCES message_polls(id) ON DELETE CASCADE,
  option_id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (option_id, user_id),
  FOREIGN KEY (poll_id, option_id) REFERENCES poll_options(poll_id, id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS poll_options_poll_position_idx
  ON poll_options(poll_id, position);

CREATE INDEX IF NOT EXISTS poll_votes_poll_user_idx
  ON poll_votes(poll_id, user_id);
