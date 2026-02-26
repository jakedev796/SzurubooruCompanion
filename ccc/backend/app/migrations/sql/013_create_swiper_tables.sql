CREATE TABLE IF NOT EXISTS swiper_seen_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    site_name VARCHAR(50) NOT NULL,
    external_id VARCHAR(255) NOT NULL,
    action VARCHAR(10) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_swiper_seen UNIQUE(user_id, site_name, external_id)
);
CREATE INDEX IF NOT EXISTS idx_swiper_seen_user ON swiper_seen_items(user_id);
CREATE INDEX IF NOT EXISTS idx_swiper_seen_lookup ON swiper_seen_items(user_id, site_name);

CREATE TABLE IF NOT EXISTS swiper_presets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    name VARCHAR(100) NOT NULL,
    sites JSONB NOT NULL DEFAULT '[]',
    tags TEXT NOT NULL DEFAULT '',
    rating VARCHAR(20) NOT NULL DEFAULT 'all',
    is_default INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_swiper_presets_user ON swiper_presets(user_id);
