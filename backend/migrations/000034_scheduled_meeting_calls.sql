ALTER TABLE calls
  ADD COLUMN IF NOT EXISTS reminder_id UUID REFERENCES reminders(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS calls_reminder_started_idx
  ON calls(reminder_id, started_at DESC)
  WHERE reminder_id IS NOT NULL;
