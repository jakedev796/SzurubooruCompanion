DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'jobs' AND column_name = 'initial_tags'
  ) THEN
    ALTER TABLE jobs ADD COLUMN initial_tags TEXT;
  END IF;
END $$;
