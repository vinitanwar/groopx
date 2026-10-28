CREATE INDEX IF NOT EXISTS messages_status_reaction_lookup_idx
  ON messages ((metadata->'status_reply'->>'id'), sender_id, created_at DESC, id DESC)
  WHERE deleted_at IS NULL
    AND COALESCE(metadata->'status_reply'->>'reaction', '') <> '';
