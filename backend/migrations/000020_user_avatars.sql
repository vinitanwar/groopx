CREATE TABLE IF NOT EXISTS user_avatars (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  content_type VARCHAR(40) NOT NULL,
  image_data BYTEA NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (octet_length(image_data) <= 5242880)
);
