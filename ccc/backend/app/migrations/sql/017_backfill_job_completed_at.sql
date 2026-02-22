UPDATE jobs SET completed_at = updated_at
WHERE LOWER(status::text) IN ('completed', 'merged') AND completed_at IS NULL;
