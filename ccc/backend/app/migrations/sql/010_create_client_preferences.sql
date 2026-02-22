CREATE TABLE IF NOT EXISTS client_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_type VARCHAR(32) NOT NULL,
    preferences JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_user_client UNIQUE(user_id, client_type)
);
CREATE INDEX IF NOT EXISTS idx_client_prefs_user ON client_preferences(user_id);
