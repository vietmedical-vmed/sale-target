-- ════════════════════════════════════════════════════════════════════════
-- Index _rev cho shared.sale_target (getRev / getChanges)
--
-- getRev (helpers.ts): rev lớn nhất toàn bảng, ORDER BY _rev DESC LIMIT 1, không lọc.
-- getChanges của admin/manager: _rev > mốc ORDER BY _rev, kèm "bu IS NULL OR bu <> 'test'"
-- và khoảng tháng kế hoạch.
-- Cả hai đang Seq Scan cả bảng (~38k dòng) rồi sắp xếp. idx_sale_target_bu_rev (bu, _rev)
-- chỉ dùng được khi lọc bu = X (PS / PM), không dùng được khi không lọc bu hoặc lọc bu <> X.
-- Hai query này chạy theo chu kỳ poll 45 s của mỗi tab đang mở.
--
-- Đo 12/11 trên prod (EXPLAIN ANALYZE):
--   getRev            : Seq Scan + top-N heapsort, đọc 2.461 block.
--   getChanges (admin): Seq Scan 2 lần (cả subquery mốc), 29,6 ms, đọc 4.925 block.
-- pg_stat_statements 15/10 → 12/11 (gộp cả bản cũ trước 07/11): getRev 14.063 lần,
-- getChanges 16.059 lần, tổng khoảng 1.400 s.
-- Sau index: getRev thành Index Only Scan Backward (vài block); getChanges quét đúng
-- khoảng _rev > mốc rồi lọc bu / tháng trên vài trăm dòng.
--
-- B-tree thường trên _rev (~1 MB). _rev hiện duy nhất và không NULL, nhưng KHÔNG đặt
-- UNIQUE: không thêm ràng buộc lên trigger cấp rev.
-- CREATE INDEX thường (không CONCURRENTLY, chạy được trong transaction như 20261107150000):
-- 38k dòng, khoá ghi sale_target dưới 1 giây, không khoá đọc. Không chạy lúc đang đồng bộ
-- thực hiện (execute_sync_job / cap_nhat_thuc_hien).
--
-- Hoàn tác: supabase/rollbacks/20261112110000_index_sale_target_rev_ROLLBACK.sql
-- ════════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_sale_target_rev
  ON shared.sale_target (_rev);

ANALYZE shared.sale_target;
