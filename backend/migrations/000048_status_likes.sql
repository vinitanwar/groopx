CREATE TABLE IF NOT EXISTS status_likes (
  status_id UUID NOT NULL REFERENCES statuses(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  liked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (status_id, user_id)
);

CREATE INDEX IF NOT EXISTS status_likes_status_idx
  ON status_likes(status_id, liked_at DESC);
