ALTER TABLE refresh_tokens
  ADD COLUMN IF NOT EXISTS device_name VARCHAR(120),
  ADD COLUMN IF NOT EXISTS user_agent TEXT,
  ADD COLUMN IF NOT EXISTS ip_address INET,
  ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

UPDATE refresh_tokens
SET device_name = COALESCE(NULLIF(device_name, ''), 'Previously signed-in device')
WHERE device_name IS NULL OR device_name = '';

CREATE INDEX IF NOT EXISTS refresh_tokens_active_sessions_idx
  ON refresh_tokens(user_id, last_seen_at DESC)
  WHERE revoked_at IS NULL;
