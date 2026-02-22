ALTER TABLE users ADD COLUMN IF NOT EXISTS szuru_category_mappings JSONB DEFAULT '{}';
