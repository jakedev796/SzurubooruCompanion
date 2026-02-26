DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'jobs' AND column_name = 'tags_from_source'
  ) THEN
    ALTER TABLE jobs ADD COLUMN tags_from_source TEXT;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'jobs' AND column_name = 'tags_from_ai'
  ) THEN
    ALTER TABLE jobs ADD COLUMN tags_from_ai TEXT;
  END IF;
END $$;
