DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'jobs' AND column_name = 'szuru_user'
  ) THEN
    ALTER TABLE jobs ADD COLUMN szuru_user VARCHAR(255);
  END IF;
END $$;
