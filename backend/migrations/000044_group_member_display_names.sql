ALTER TABLE conversation_members
    ADD COLUMN IF NOT EXISTS group_display_name VARCHAR(80);

ALTER TABLE conversation_members
    ALTER COLUMN group_display_name TYPE VARCHAR(80);
