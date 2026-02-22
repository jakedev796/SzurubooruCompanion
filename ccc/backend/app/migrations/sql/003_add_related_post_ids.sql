DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'jobs' AND column_name = 'related_post_ids'
  ) THEN
    ALTER TABLE jobs ADD COLUMN related_post_ids INTEGER[] DEFAULT '{}';
  END IF;
END $$;
