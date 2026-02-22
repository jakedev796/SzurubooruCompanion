CREATE TABLE IF NOT EXISTS tag_cache (
    tag_name    VARCHAR(512) PRIMARY KEY,
    category    VARCHAR(128) NOT NULL,
    verified_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
