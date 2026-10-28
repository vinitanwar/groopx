ALTER TABLE reminders
  ADD COLUMN IF NOT EXISTS repeat_rule VARCHAR(16) NOT NULL DEFAULT 'none';

ALTER TABLE reminders
  ADD COLUMN IF NOT EXISTS repeat_anchor_day SMALLINT;

DO $$
BEGIN
  ALTER TABLE reminders
    ADD CONSTRAINT reminders_repeat_rule_check
    CHECK (repeat_rule IN ('none', 'daily', 'weekly', 'monthly'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE reminders
    ADD CONSTRAINT reminders_repeat_anchor_day_check
    CHECK (repeat_anchor_day IS NULL OR repeat_anchor_day BETWEEN 1 AND 31);
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS reminders_user_repeat_schedule_idx
  ON reminders(user_id, repeat_rule, scheduled_at)
  WHERE status = 'upcoming' AND repeat_rule <> 'none';
