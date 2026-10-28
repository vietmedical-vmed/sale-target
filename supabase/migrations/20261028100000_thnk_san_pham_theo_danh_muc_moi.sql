-- Kế hoạch BU THNS & CSVT (bu 'thnk', FY26) đổi tên sản phẩm theo danh mục mới.
--
-- 28/10 user cập nhật dm_vat_tu / dm_bo_vat_tu_mapping của THNK: cột san_pham đổi cấp,
-- nhiều-nhiều so với tên cũ trên kế hoạch và hoá đơn. Ví dụ:
--   * gộp: các loại băng dán / gạc CSVT → "Băng dán vô trùng các loại";
--          "Bình chứa dịch", "PICO 7"... → "Hút áp lực âm";
--   * tách: "Điện cực" → "Điện cực trung tính liền dây người lớn" / "trẻ em" / "trẻ sơ sinh"...;
--           "Tay dao hàn mạch mổ mở" → "Tay dao hàn mạch (LF2019)" / "(LF1212)"...
--
-- Ánh xạ theo từng (nhóm, SP cũ, đơn giá) của kế hoạch:
--   1. Ứng viên SP mới = SP danh mục của các mã vật tư đã xuất hoá đơn dưới tên cũ
--      (hoa_don_bovattu.ma_vat_tu = dm_vat_tu.ma_bravo) ∪ SP danh mục có ten_vat_tu trùng tên
--      cũ (bỏ hậu tố " 1"/" 2") ∪ tên cũ nếu vẫn còn trong danh mục. Cùng nhóm SP.
--   2. Một ứng viên → đổi thẳng ('1-1').
--   3. Nhiều ứng viên → SP có giá vật tư khớp đơn giá kế hoạch (±2đ, so thầu mới / thầu cũ,
--      có hoặc không chia 1.05). Khớp đúng 1 → 'gia'.
--   4. Còn lại → SP có giá gần nhất; hoà thì SP xuất hoá đơn nhiều nhất dưới tên cũ
--      ('gan_nhat', user chốt 28/10). SP không có giá (bàn đạp, KIT, bộ chuyển đổi) chỉ
--      được chọn khi không còn ứng viên nào có giá.
-- Bảng ánh xạ lưu ở backup.thnk_doi_ten_sp_20261028.
--
-- Đổi tên làm nhiều dòng về cùng khoá → hoãn uq_sale_target_khoa, gộp bằng
-- gop_dong_trung_sale_target (cộng SL / DThu). Quota đi theo khoá mới nhờ
-- trg_sale_target_giu_khoa_quota. Dòng ngoài kế hoạch không đổi: lần đồng bộ thực hiện
-- tiếp theo tự xoá và tạo lại theo tên hoá đơn mới.
--
-- Hoá đơn: hoa_don_bovattu.san_pham lấy từ cột "Sản phẩm (gộp)" của file nạp (pipeline
-- ngoài repo) nên vẫn mang tên cũ. Đổi theo danh mục (mã vật tư → dm_vat_tu.ma_bravo, chỉ
-- khi mã ra đúng 1 SP cùng nhóm) và thêm trigger để các lần nạp sau cũng lấy tên danh mục.
-- Ngày 28/10 CH&CS và CTTM đã khớp danh mục 100% nên chỉ hoá đơn THNK đổi.
--
-- Sau migration phải chạy "Cập nhật thực hiện" (start_sync_job) để số về đúng dòng.
-- Hoàn tác: supabase/rollbacks/20261028100000_thnk_san_pham_theo_danh_muc_moi_ROLLBACK.sql

BEGIN;

CREATE TABLE backup.bak_20261028_thnk_sale_target AS
SELECT * FROM shared.sale_target WHERE nam_tai_chinh = 'FY26' AND bu = 'thnk';
ALTER TABLE backup.bak_20261028_thnk_sale_target ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON backup.bak_20261028_thnk_sale_target FROM PUBLIC, anon, authenticated;

CREATE TABLE backup.bak_20261028_thnk_quota_thau AS
SELECT * FROM shared.quota_thau
WHERE nhom_san_pham IN (SELECT nhom_san_pham FROM shared.dm_nhom_san_pham WHERE bu_code = 'thnk');
ALTER TABLE backup.bak_20261028_thnk_quota_thau ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON backup.bak_20261028_thnk_quota_thau FROM PUBLIC, anon, authenticated;

CREATE TABLE backup.bak_20261028_thnk_dot_thau AS
SELECT * FROM shared.dot_thau
WHERE nhom_san_pham IN (SELECT nhom_san_pham FROM shared.dm_nhom_san_pham WHERE bu_code = 'thnk');
ALTER TABLE backup.bak_20261028_thnk_dot_thau ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON backup.bak_20261028_thnk_dot_thau FROM PUBLIC, anon, authenticated;

CREATE TABLE backup.bak_20261028_hoa_don_san_pham AS
SELECT id, so_tai_lieu, ngay_tai_lieu, ma_kh, ma_vat_tu, nhom_san_pham, bo_vat_tu, san_pham
FROM app_sale.hoa_don_bovattu;
ALTER TABLE backup.bak_20261028_hoa_don_san_pham ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON backup.bak_20261028_hoa_don_san_pham FROM PUBLIC, anon, authenticated;

-- ── Ánh xạ SP cũ → mới ──────────────────────────────────────────────────────
CREATE TABLE backup.thnk_doi_ten_sp_20261028 AS
WITH v AS (SELECT * FROM shared.dm_vat_tu WHERE bu_code = 'thnk'),
hd AS (
  SELECT h.san_pham AS cu, v.nhom_san_pham AS nhom, v.san_pham AS moi, count(*) AS n
  FROM app_sale.hoa_don_bovattu h JOIN v ON v.ma_bravo = h.ma_vat_tu
  GROUP BY 1, 2, 3),
p AS (
  SELECT nhom_san_pham AS nhom, san_pham AS cu, coalesce(don_gia, 0) AS g
  FROM shared.sale_target
  WHERE nam_tai_chinh = 'FY26' AND bu = 'thnk' AND NOT coalesce(ngoai_ke_hoach, false)
  GROUP BY 1, 2, 3),
m AS (
  SELECT cu, nhom, moi FROM hd
  UNION
  SELECT DISTINCT p.cu, v.nhom_san_pham, v.san_pham
  FROM p JOIN v ON v.nhom_san_pham = p.nhom
   AND lower(btrim(v.ten_vat_tu)) = lower(regexp_replace(btrim(p.cu), '\s+\d$', ''))
  UNION
  SELECT DISTINCT p.cu, v.nhom_san_pham, v.san_pham
  FROM p JOIN v ON v.nhom_san_pham = p.nhom AND v.san_pham = btrim(p.cu)
  UNION
  SELECT DISTINCT p.cu, hd.nhom, hd.moi
  FROM p JOIN hd ON hd.nhom = p.nhom AND hd.cu = btrim(p.cu)),
c AS (
  SELECT p.nhom, p.cu, p.g, m.moi,
    count(*) OVER (PARTITION BY p.nhom, p.cu, p.g) AS so_ung_vien,
    coalesce((SELECT sum(hd.n) FROM hd WHERE hd.cu = btrim(p.cu) AND hd.moi = m.moi), 0) AS so_hd,
    (SELECT min(abs(x - p.g))
       FROM v, unnest(ARRAY[v.don_gia_thau_moi, v.don_gia_thau_cu,
                            v.don_gia_thau_moi / 1.05, v.don_gia_thau_cu / 1.05]) x
      WHERE v.san_pham = m.moi AND v.nhom_san_pham = p.nhom AND x > 0) AS lech
  FROM p JOIN m ON m.cu = p.cu AND m.nhom = p.nhom),
r AS (
  SELECT c.*,
    count(*) FILTER (WHERE lech <= 2) OVER (PARTITION BY nhom, cu, g) AS so_khop_gia,
    row_number() OVER (PARTITION BY nhom, cu, g
      ORDER BY (lech IS NULL), (lech <= 2) DESC, lech, so_hd DESC, moi) AS rn
  FROM c)
SELECT nhom AS nhom_san_pham, cu AS san_pham_cu, g AS don_gia, moi AS san_pham_moi,
       CASE WHEN so_ung_vien = 1 THEN '1-1'
            WHEN lech <= 2 AND so_khop_gia = 1 THEN 'gia'
            ELSE 'gan_nhat' END AS cach,
       so_ung_vien, lech, so_hd
FROM r WHERE rn = 1;
ALTER TABLE backup.thnk_doi_ten_sp_20261028 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON backup.thnk_doi_ten_sp_20261028 FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM shared.sale_target s
    WHERE s.nam_tai_chinh = 'FY26' AND s.bu = 'thnk' AND NOT coalesce(s.ngoai_ke_hoach, false)
      AND NOT EXISTS (SELECT 1 FROM backup.thnk_doi_ten_sp_20261028 m
                      WHERE m.nhom_san_pham = s.nhom_san_pham AND m.san_pham_cu = s.san_pham
                        AND m.don_gia = coalesce(s.don_gia, 0))) THEN
    RAISE EXCEPTION 'Còn dòng kế hoạch THNK chưa có SP mới';
  END IF;
END $$;

-- ── Đổi tên kế hoạch ────────────────────────────────────────────────────────
SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

CREATE TEMP TABLE _doi_ten ON COMMIT DROP AS
WITH u AS (
  UPDATE shared.sale_target s SET
    san_pham   = m.san_pham_moi,
    updated_at = now()
  FROM backup.thnk_doi_ten_sp_20261028 m
  WHERE s.nam_tai_chinh = 'FY26' AND s.bu = 'thnk' AND NOT coalesce(s.ngoai_ke_hoach, false)
    AND m.nhom_san_pham = s.nhom_san_pham AND m.san_pham_cu = s.san_pham
    AND m.don_gia = coalesce(s.don_gia, 0)
    AND s.san_pham IS DISTINCT FROM m.san_pham_moi
  RETURNING s.id
)
SELECT id FROM u;

SELECT shared.gop_dong_trung_sale_target((SELECT array_agg(id) FROM _doi_ten));

SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;

-- ── Quota trigger để lại ────────────────────────────────────────────────────
-- Nhiều SP cũ gộp về 1 SP mới: quota cùng loại × đợt của SP thứ hai bị trigger để lại
-- (giu_khoa_xung_dot) thành mồ côi. Kế hoạch đã cộng SL khi gộp dòng nên quota cũng cộng
-- vào quota đích. Chỉ xử lý quota đang hiện trước migration (khoá cũ có dòng kế hoạch).
CREATE TEMP TABLE _q_con ON COMMIT DROP AS
SELECT q.id, q.so_luong, m.san_pham_moi
FROM shared.quota_thau q
JOIN backup.thnk_doi_ten_sp_20261028 m
  ON m.nhom_san_pham = q.nhom_san_pham AND m.san_pham_cu = q.san_pham AND m.don_gia = q.don_gia
WHERE q.nam_tai_chinh = 'FY26' AND m.san_pham_moi <> q.san_pham
  AND EXISTS (SELECT 1 FROM backup.bak_20261028_thnk_sale_target s
              WHERE s.ps = q.ps AND s.ma_khach_hang = q.ma_khach_hang
                AND s.nhom_san_pham = q.nhom_san_pham AND s.bo_vat_tu = q.bo_vat_tu
                AND s.san_pham = q.san_pham AND coalesce(s.don_gia, 0) = q.don_gia
                AND NOT coalesce(s.ngoai_ke_hoach, false))
  AND NOT EXISTS (SELECT 1 FROM shared.sale_target s
                  WHERE s.nam_tai_chinh = q.nam_tai_chinh AND s.ps = q.ps
                    AND s.ma_khach_hang = q.ma_khach_hang AND s.nhom_san_pham = q.nhom_san_pham
                    AND s.bo_vat_tu = q.bo_vat_tu AND s.san_pham = q.san_pham
                    AND coalesce(s.don_gia, 0) = q.don_gia AND NOT coalesce(s.ngoai_ke_hoach, false));

CREATE TEMP TABLE _q_dich ON COMMIT DROP AS
SELECT c.id, d.id AS dich_id, c.so_luong
FROM _q_con c
JOIN shared.quota_thau q ON q.id = c.id
JOIN shared.quota_thau d
  ON d.nam_tai_chinh = q.nam_tai_chinh AND d.ps = q.ps AND d.ma_khach_hang = q.ma_khach_hang
 AND d.nhom_san_pham = q.nhom_san_pham AND d.bo_vat_tu = q.bo_vat_tu
 AND d.san_pham = c.san_pham_moi AND d.don_gia = q.don_gia
 AND d.loai = q.loai AND d.dot IS NOT DISTINCT FROM q.dot;

INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'thnk_doi_ten_sp_cong_quota', 'quota_thau', q.id, to_jsonb(q), jsonb_build_object('cong_vao', g.dich_id)
FROM _q_dich g JOIN shared.quota_thau q ON q.id = g.id;

UPDATE shared.quota_thau d SET so_luong = d.so_luong + t.sl, updated_at = now()
FROM (SELECT dich_id, sum(so_luong) AS sl FROM _q_dich GROUP BY 1) t
WHERE d.id = t.dich_id;

DELETE FROM shared.quota_thau WHERE id IN (SELECT id FROM _q_dich);

-- Không có quota đích (khoá cũ bị tách) → chuyển thẳng sang SP mới.
INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'thnk_doi_ten_sp_chuyen_quota', 'quota_thau', q.id, to_jsonb(q), jsonb_build_object('san_pham', c.san_pham_moi)
FROM _q_con c JOIN shared.quota_thau q ON q.id = c.id
WHERE c.id NOT IN (SELECT id FROM _q_dich);

UPDATE shared.quota_thau q SET san_pham = c.san_pham_moi, updated_at = now()
FROM _q_con c
WHERE q.id = c.id AND c.id NOT IN (SELECT id FROM _q_dich);

-- ── Hoá đơn lấy tên SP theo danh mục ───────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_dm_vat_tu_ma_bravo ON shared.dm_vat_tu (ma_bravo);

CREATE OR REPLACE FUNCTION app_sale.san_pham_theo_danh_muc()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = app_sale, shared, public
AS $$
DECLARE
  v_sp text;
BEGIN
  IF nullif(btrim(NEW.ma_vat_tu), '') IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT min(v.san_pham) INTO v_sp
  FROM shared.dm_vat_tu v
  WHERE v.ma_bravo = NEW.ma_vat_tu AND v.nhom_san_pham = NEW.nhom_san_pham
    AND nullif(btrim(v.san_pham), '') IS NOT NULL
  HAVING count(DISTINCT v.san_pham) = 1;
  IF v_sp IS NOT NULL THEN
    NEW.san_pham := v_sp;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION app_sale.san_pham_theo_danh_muc() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_hoa_don_san_pham_theo_danh_muc ON app_sale.hoa_don_bovattu;
CREATE TRIGGER trg_hoa_don_san_pham_theo_danh_muc
BEFORE INSERT OR UPDATE OF ma_vat_tu, nhom_san_pham, san_pham ON app_sale.hoa_don_bovattu
FOR EACH ROW EXECUTE FUNCTION app_sale.san_pham_theo_danh_muc();

-- Chạy trigger cho hoá đơn đang có tên khác danh mục.
UPDATE app_sale.hoa_don_bovattu h SET san_pham = h.san_pham
WHERE EXISTS (
  SELECT 1 FROM shared.dm_vat_tu v
  WHERE v.ma_bravo = h.ma_vat_tu AND v.nhom_san_pham = h.nhom_san_pham
    AND v.san_pham IS DISTINCT FROM h.san_pham);

COMMIT;
