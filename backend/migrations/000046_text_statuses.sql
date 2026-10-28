ALTER TABLE statuses
  ALTER COLUMN media_id DROP NOT NULL;

ALTER TABLE statuses
  ADD COLUMN IF NOT EXISTS text_content VARCHAR(700),
  ADD COLUMN IF NOT EXISTS background_color VARCHAR(9) NOT NULL DEFAULT '#6335FF';

ALTER TABLE statuses
  DROP CONSTRAINT IF EXISTS statuses_media_type_check;

ALTER TABLE statuses
  ADD CONSTRAINT statuses_media_type_check
  CHECK (media_type IN ('image', 'video', 'text'));

ALTER TABLE statuses
  DROP CONSTRAINT IF EXISTS statuses_content_check;

ALTER TABLE statuses
  ADD CONSTRAINT statuses_content_check
  CHECK (
    (media_type = 'text' AND media_id IS NULL AND COALESCE(LENGTH(BTRIM(text_content)), 0) > 0)
    OR
    (media_type IN ('image', 'video') AND media_id IS NOT NULL)
  );

ALTER TABLE statuses
  DROP CONSTRAINT IF EXISTS statuses_background_color_check;

ALTER TABLE statuses
  ADD CONSTRAINT statuses_background_color_check
  CHECK (
    media_type <> 'text'
    OR background_color IN ('#6335FF', '#E91E63', '#0F8B8D', '#1565C0', '#F57C00', '#263238', '#7B1FA2', '#2E7D32')
  );
