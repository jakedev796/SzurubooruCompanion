CREATE TABLE IF NOT EXISTS global_settings (
    key VARCHAR(255) PRIMARY KEY,
    value TEXT,
    value_type VARCHAR(32) NOT NULL DEFAULT 'string',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
