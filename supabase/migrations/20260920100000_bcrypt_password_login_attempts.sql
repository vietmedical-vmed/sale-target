-- GĐ 3: bcrypt password + login rate limiting
-- Adds password_bcrypt column for transparent re-hash from SHA-256
-- Adds login_attempts table for brute-force protection

ALTER TABLE shared.users
  ADD COLUMN IF NOT EXISTS password_bcrypt text;

COMMENT ON COLUMN shared.users.password_bcrypt IS
  'bcrypt hash — khi có, dùng thay SHA-256. Tự gán khi login đúng lần đầu sau nâng cấp.';

-- Login attempts tracking
CREATE TABLE IF NOT EXISTS shared.login_attempts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  username text NOT NULL,
  attempted_at timestamptz NOT NULL DEFAULT now(),
  success boolean NOT NULL DEFAULT false,
  ip text
);

CREATE INDEX IF NOT EXISTS idx_login_attempts_user_time
  ON shared.login_attempts (username, attempted_at DESC);

-- Auto-cleanup: drop rows older than 24h (pg_cron or manual)
COMMENT ON TABLE shared.login_attempts IS
  'Rate-limit: 5 failed in 15 min = lockout. Purge rows > 24h.';

-- RLS: only service_role can read/write
ALTER TABLE shared.login_attempts ENABLE ROW LEVEL SECURITY;
-- No policies = only service_role (bypasses RLS) can access
