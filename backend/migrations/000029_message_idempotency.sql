ALTER TABLE messages ADD COLUMN IF NOT EXISTS client_message_id VARCHAR(80);

DO $$ BEGIN
  ALTER TABLE messages
    ADD CONSTRAINT messages_sender_client_message_unique
    UNIQUE (sender_id, client_message_id);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
