CREATE UNIQUE INDEX IF NOT EXISTS contacts_owner_user_unique
  ON contacts(owner_id, contact_user_id)
  WHERE contact_user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS conversation_members_conversation_role_idx
  ON conversation_members(conversation_id, role);
