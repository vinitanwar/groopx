CREATE TABLE IF NOT EXISTS meeting_attendees (
  meeting_id UUID NOT NULL REFERENCES reminders(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  response VARCHAR(16) NOT NULL DEFAULT 'pending',
  responded_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (meeting_id, user_id),
  CONSTRAINT meeting_attendees_response_check
    CHECK (response IN ('pending', 'accepted', 'declined'))
);

CREATE INDEX IF NOT EXISTS meeting_attendees_user_response_idx
  ON meeting_attendees(user_id, response, meeting_id);
