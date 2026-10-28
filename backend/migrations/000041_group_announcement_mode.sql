ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS announcement_only BOOLEAN NOT NULL DEFAULT FALSE;

CREATE OR REPLACE FUNCTION enforce_group_announcement_sender()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.deleted_at IS NOT NULL OR NEW.body IS NOT DISTINCT FROM OLD.body THEN
      RETURN NEW;
    END IF;
  END IF;

  IF NEW.sender_id IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM conversations conversation
       WHERE conversation.id = NEW.conversation_id
         AND conversation.kind = 'group'
         AND conversation.announcement_only
     )
     AND NOT EXISTS (
       SELECT 1
       FROM conversation_members member
       WHERE member.conversation_id = NEW.conversation_id
         AND member.user_id = NEW.sender_id
         AND member.role = 'admin'
     )
  THEN
    RAISE EXCEPTION 'only group admins can send messages in announcement mode'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS messages_group_announcement_sender ON messages;
CREATE TRIGGER messages_group_announcement_sender
BEFORE INSERT OR UPDATE OF body ON messages
FOR EACH ROW EXECUTE FUNCTION enforce_group_announcement_sender();
