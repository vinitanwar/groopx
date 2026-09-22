ALTER TABLE reminders
  ADD COLUMN IF NOT EXISTS notified_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS reminders_due_idx
  ON reminders(scheduled_at)
  WHERE status = 'upcoming' AND notified_at IS NULL;
