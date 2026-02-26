CREATE TABLE IF NOT EXISTS site_credentials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    site_name VARCHAR(64) NOT NULL,
    credential_key VARCHAR(128) NOT NULL,
    credential_value_encrypted TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_user_site_cred UNIQUE(user_id, site_name, credential_key)
);
CREATE INDEX IF NOT EXISTS idx_site_creds_user ON site_credentials(user_id);
