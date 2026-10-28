CREATE TABLE IF NOT EXISTS live_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL UNIQUE REFERENCES messages(id) ON DELETE CASCADE,
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  tracking_key VARCHAR(128) NOT NULL,
  latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  accuracy_meters DOUBLE PRECISION NOT NULL DEFAULT 0 CHECK (accuracy_meters BETWEEN 0 AND 5000),
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  stopped_at TIMESTAMPTZ,
  CHECK (expires_at > started_at)
);

CREATE UNIQUE INDEX IF NOT EXISTS live_locations_owner_conversation_active_idx
  ON live_locations(owner_id, conversation_id)
  WHERE stopped_at IS NULL;

CREATE INDEX IF NOT EXISTS live_locations_expiry_idx
  ON live_locations(expires_at)
  WHERE stopped_at IS NULL;

CREATE INDEX IF NOT EXISTS live_locations_owner_active_idx
  ON live_locations(owner_id, expires_at)
  WHERE stopped_at IS NULL;

CREATE INDEX IF NOT EXISTS live_locations_device_active_idx
  ON live_locations(owner_id, tracking_key, expires_at)
  WHERE stopped_at IS NULL;
