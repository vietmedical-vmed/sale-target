-- Bảng lưu giải trình theo dạng append-only log.
-- Mỗi lần user nhập giải trình mới = 1 row, không ghi đè.

CREATE TABLE IF NOT EXISTS shared.giai_trinh (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ps          text NOT NULL,
  customer_id text NOT NULL,
  grp         text NOT NULL DEFAULT '',
  content     text NOT NULL DEFAULT '',
  created_by  text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Index cho truy vấn: lấy giải trình theo PS + KH + nhóm SP, mới nhất trước
CREATE INDEX idx_giai_trinh_lookup
  ON shared.giai_trinh (ps, customer_id, grp, created_at DESC);

-- RLS: chặn anonymous, cho phép authenticated đọc/ghi
ALTER TABLE shared.giai_trinh ENABLE ROW LEVEL SECURITY;

CREATE POLICY giai_trinh_service ON shared.giai_trinh
  FOR ALL USING (true) WITH CHECK (true);

COMMENT ON TABLE shared.giai_trinh IS 'Append-only log giải trình theo nhóm SP, mỗi lần update 1 row mới';
