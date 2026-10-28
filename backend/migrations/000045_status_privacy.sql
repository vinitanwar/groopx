CREATE TABLE IF NOT EXISTS status_privacy_settings (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  audience VARCHAR(24) NOT NULL DEFAULT 'contacts'
    CHECK (audience IN ('contacts', 'contacts_except', 'only_share_with')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS status_privacy_contacts (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  contact_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, contact_user_id),
  CHECK (user_id <> contact_user_id)
);

CREATE TABLE IF NOT EXISTS muted_status_users (
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  muted_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (owner_id, muted_user_id),
  CHECK (owner_id <> muted_user_id)
);

CREATE INDEX IF NOT EXISTS status_privacy_contacts_contact_idx
  ON status_privacy_contacts(contact_user_id, user_id);

CREATE INDEX IF NOT EXISTS muted_status_users_muted_idx
  ON muted_status_users(muted_user_id, owner_id);
