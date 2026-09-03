-- Migration: audit_log + app_config
-- Bảng ghi lịch sử thao tác và cấu hình ứng dụng

-- 1. Bảng audit_log — ghi mọi thao tác ghi dữ liệu
CREATE TABLE IF NOT EXISTS shared.audit_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  username    text NOT NULL,
  ho_ten      text,
  role        text,
  bu          text,
  action      text NOT NULL,
  row_count   int NOT NULL DEFAULT 0,
  details     jsonb,
  thang_ke_hoach text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_log_created ON shared.audit_log (created_at DESC);
CREATE INDEX idx_audit_log_username ON shared.audit_log (username);
CREATE INDEX idx_audit_log_bu ON shared.audit_log (bu);

GRANT ALL ON shared.audit_log TO service_role;

-- 2. Bảng app_config — cấu hình chung (deadline, v.v.)
CREATE TABLE IF NOT EXISTS shared.app_config (
  key         text PRIMARY KEY,
  value       jsonb NOT NULL DEFAULT '{}',
  updated_at  timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON shared.app_config TO service_role;

-- Seed: deadline mặc định ngày 5
INSERT INTO shared.app_config (key, value)
VALUES ('deadline_day', '5'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- RLS bật nhưng service_role bypass
ALTER TABLE shared.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared.app_config ENABLE ROW LEVEL SECURITY;
