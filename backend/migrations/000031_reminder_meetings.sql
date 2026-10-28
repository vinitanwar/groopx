ALTER TABLE reminders
  ADD COLUMN IF NOT EXISTS item_type VARCHAR(16) NOT NULL DEFAULT 'reminder';

ALTER TABLE reminders
  ADD COLUMN IF NOT EXISTS call_kind call_kind;

DO $$
BEGIN
  ALTER TABLE reminders
    ADD CONSTRAINT reminders_item_type_check
    CHECK (item_type IN ('reminder', 'meeting'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE reminders
    ADD CONSTRAINT reminders_meeting_chat_check
    CHECK (item_type <> 'meeting' OR (conversation_id IS NOT NULL AND call_kind IS NOT NULL));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS reminders_user_type_schedule_idx
  ON reminders(user_id, item_type, scheduled_at);
