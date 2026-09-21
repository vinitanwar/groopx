CREATE TABLE IF NOT EXISTS community_groups (
  community_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  group_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  added_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (community_id, group_id),
  CHECK (community_id <> group_id)
);

CREATE INDEX IF NOT EXISTS community_groups_group_idx ON community_groups(group_id);
