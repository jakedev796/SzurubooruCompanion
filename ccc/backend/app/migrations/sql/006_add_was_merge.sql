DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'jobs' AND column_name = 'was_merge'
  ) THEN
    ALTER TABLE jobs ADD COLUMN was_merge INTEGER NOT NULL DEFAULT 0;
  END IF;
END $$;
