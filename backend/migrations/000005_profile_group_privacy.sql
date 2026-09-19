ALTER TABLE users ADD COLUMN IF NOT EXISTS bio VARCHAR(280);

ALTER TABLE conversation_members
  ADD COLUMN IF NOT EXISTS group_display_name VARCHAR(50);

-- A private group never exposes a member phone number. API queries must select
-- username/full_name/group_display_name only, and direct-chat creation must not
-- accept a private-group membership as permission to contact another member.
CREATE INDEX IF NOT EXISTS conversation_members_conversation_role_idx
  ON conversation_members(conversation_id, role);
