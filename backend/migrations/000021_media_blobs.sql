CREATE TABLE IF NOT EXISTS media_blobs (
  media_id UUID PRIMARY KEY REFERENCES media_objects(id) ON DELETE CASCADE,
  file_data BYTEA NOT NULL,
  CHECK (octet_length(file_data) <= 26214400)
);
