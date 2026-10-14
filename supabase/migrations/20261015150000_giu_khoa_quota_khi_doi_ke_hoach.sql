-- P3 chuẩn hoá quota: giữ liên kết quota_thau / dot_thau khi khoá của dòng kế hoạch đổi.
--
-- Khoá quota  = năm × PS × KH × nhóm × BVT × sản phẩm × giá (quota_thau).
-- Khoá đợt    = năm × PS × KH × nhóm (dot_thau).
-- Khoá đổi qua: sửa tên SP / BVT / giá (update_sale_target_cells), đổi PS theo địa
-- bàn (apply_dia_ban_to_plan), sửa tay trên dashboard... Trước đây quota ở lại khoá cũ
-- và thành mồ côi (không lên app).
--
-- Hai trigger trên sale_target (không dùng transition table: chụp toàn bộ dòng của mọi
-- câu UPDATE làm đồng bộ thực hiện chậm gấp đôi):
--   * AFTER UPDATE OF <cột khoá> FOR EACH ROW WHEN (khoá đổi): ghi cặp khoá cũ → mới
--     vào bảng tạm _gk_doi. Dòng không đổi khoá không tốn gì.
--   * AFTER UPDATE FOR EACH STATEMENT: xử lý _gk_doi (nếu có) rồi xoá trắng. AFTER ROW
--     chạy xong trước AFTER STATEMENT nên lúc này đã thấy đủ mọi dòng của câu lệnh.
-- Quy tắc xử lý:
--   * Nhóm cũ không còn dòng kế hoạch nào và mọi dòng sang đúng 1 nhóm mới → chuyển
--     đợt sang nhóm mới (đợt trùng số: cùng tháng thì gộp, khác tháng thì để lại + log).
--   * Khoá quota cũ không còn dòng kế hoạch nào và mọi dòng sang đúng 1 khoá mới →
--     chuyển quota sang khoá mới. Nếu khoá mới đã có quota cùng loại × đợt, hoặc nhóm
--     mới có đợt cùng số nhưng khác tháng → để lại + log. Đợt chưa có ở nhóm mới thì
--     chép từ nhóm cũ.
--   * Khoá cũ còn dòng (tách khoá, vd đổi PS từ một tháng) hoặc sang nhiều khoá → không
--     tự chuyển, log 'giu_khoa_tach' nếu khoá cũ có quota.
-- Sửa tay từng dòng: quota chuyển khi dòng cuối của khoá cũ được sửa.
-- Dòng ngoài kế hoạch (ngoai_ke_hoach) không tính. Mọi thay đổi / bỏ qua ghi vào
-- shared.quota_chuan_hoa_log (buoc giu_khoa_*).

BEGIN;

CREATE OR REPLACE FUNCTION shared.ghi_doi_khoa_sale_target()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = shared, public
AS $$
BEGIN
  IF coalesce(OLD.ngoai_ke_hoach, false) OR coalesce(NEW.ngoai_ke_hoach, false) THEN
    RETURN NULL;
  END IF;
  IF to_regclass('pg_temp._gk_doi') IS NULL THEN
    CREATE TEMP TABLE _gk_doi (
      o_fy text, o_ps text, o_cust text, o_grp text, o_mset text, o_prod text, o_gia numeric,
      n_fy text, n_ps text, n_cust text, n_grp text, n_mset text, n_prod text, n_gia numeric,
      n_bu text, n_mien text, n_kh text
    ) ON COMMIT DROP;
  END IF;
  INSERT INTO _gk_doi VALUES (
    OLD.nam_tai_chinh, coalesce(OLD.ps,''), coalesce(OLD.ma_khach_hang,''), coalesce(OLD.nhom_san_pham,''),
    coalesce(OLD.bo_vat_tu,''), coalesce(OLD.san_pham,''), coalesce(OLD.don_gia,0),
    NEW.nam_tai_chinh, coalesce(NEW.ps,''), coalesce(NEW.ma_khach_hang,''), coalesce(NEW.nhom_san_pham,''),
    coalesce(NEW.bo_vat_tu,''), coalesce(NEW.san_pham,''), coalesce(NEW.don_gia,0),
    NEW.bu, NEW.mien, NEW.khach_hang);
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION shared.giu_khoa_quota_sale_target()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = shared, public
AS $$
DECLARE
  g record;
  k record;
  q record;
  d record;
  v_dich record;
BEGIN
  IF to_regclass('pg_temp._gk_doi') IS NULL THEN
    RETURN NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM _gk_doi) THEN
    RETURN NULL;
  END IF;

  -- 1) Đợt thầu theo nhóm
  FOR g IN
    SELECT o_fy, o_ps, o_cust, o_grp,
           count(DISTINCT (n_fy, n_ps, n_cust, n_grp)) n_dich,
           min(n_fy) n_fy, min(n_ps) n_ps, min(n_cust) n_cust, min(n_grp) n_grp, min(n_bu) n_bu, min(n_mien) n_mien
    FROM _gk_doi
    WHERE (o_fy, o_ps, o_cust, o_grp) IS DISTINCT FROM (n_fy, n_ps, n_cust, n_grp)
    GROUP BY 1,2,3,4
  LOOP
    CONTINUE WHEN g.n_dich <> 1;
    CONTINUE WHEN EXISTS (SELECT 1 FROM shared.sale_target s
                          WHERE s.nam_tai_chinh = g.o_fy AND coalesce(s.ps,'') = g.o_ps
                            AND coalesce(s.ma_khach_hang,'') = g.o_cust AND coalesce(s.nhom_san_pham,'') = g.o_grp
                            AND NOT coalesce(s.ngoai_ke_hoach, false));
    FOR d IN SELECT * FROM shared.dot_thau
             WHERE nam_tai_chinh = g.o_fy AND ps = g.o_ps AND ma_khach_hang = g.o_cust AND nhom_san_pham = g.o_grp
    LOOP
      SELECT * INTO v_dich FROM shared.dot_thau
      WHERE nam_tai_chinh = g.n_fy AND ps = g.n_ps AND ma_khach_hang = g.n_cust AND nhom_san_pham = g.n_grp
        AND loai = d.loai AND dot = d.dot;
      IF NOT FOUND THEN
        UPDATE shared.dot_thau SET nam_tai_chinh = g.n_fy, ps = g.n_ps, ma_khach_hang = g.n_cust,
               nhom_san_pham = g.n_grp, bu = coalesce(g.n_bu, bu), mien = coalesce(g.n_mien, mien),
               updated_at = now(), updated_by = 'giu_khoa'
        WHERE id = d.id;
        INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
        SELECT 'giu_khoa', 'dot_thau', d.id, to_jsonb(d), to_jsonb(x) FROM shared.dot_thau x WHERE x.id = d.id;
      ELSIF v_dich.thang_thau IS NOT DISTINCT FROM d.thang_thau THEN
        -- Nhóm mới đã có đúng đợt đó (cùng tháng): gộp, bỏ đợt cũ.
        DELETE FROM shared.dot_thau WHERE id = d.id;
        INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
        VALUES ('giu_khoa_gop_dot', 'dot_thau', d.id, to_jsonb(d), to_jsonb(v_dich));
      ELSE
        INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
        VALUES ('giu_khoa_xung_dot', 'dot_thau', d.id, to_jsonb(d), to_jsonb(v_dich));
      END IF;
    END LOOP;
  END LOOP;

  -- 2) Quota theo khoá sản phẩm × giá
  FOR k IN
    SELECT o_fy, o_ps, o_cust, o_grp, o_mset, o_prod, o_gia,
           count(DISTINCT (n_fy, n_ps, n_cust, n_grp, n_mset, n_prod, n_gia)) n_dich,
           min(n_fy) n_fy, min(n_ps) n_ps, min(n_cust) n_cust, min(n_grp) n_grp, min(n_mset) n_mset,
           min(n_prod) n_prod, min(n_gia) n_gia, min(n_bu) n_bu, min(n_mien) n_mien, min(n_kh) n_kh
    FROM _gk_doi GROUP BY 1,2,3,4,5,6,7
  LOOP
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM shared.quota_thau
                              WHERE nam_tai_chinh = k.o_fy AND ps = k.o_ps AND ma_khach_hang = k.o_cust
                                AND nhom_san_pham = k.o_grp AND bo_vat_tu = k.o_mset AND san_pham = k.o_prod
                                AND don_gia = k.o_gia);
    IF k.n_dich <> 1 OR EXISTS (
         SELECT 1 FROM shared.sale_target s
         WHERE s.nam_tai_chinh = k.o_fy AND coalesce(s.ps,'') = k.o_ps AND coalesce(s.ma_khach_hang,'') = k.o_cust
           AND coalesce(s.nhom_san_pham,'') = k.o_grp AND coalesce(s.bo_vat_tu,'') = k.o_mset
           AND coalesce(s.san_pham,'') = k.o_prod AND coalesce(s.don_gia,0) = k.o_gia
           AND NOT coalesce(s.ngoai_ke_hoach, false)) THEN
      INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, truoc, sau)
      VALUES ('giu_khoa_tach', 'quota_thau', to_jsonb(k), NULL);
      CONTINUE;
    END IF;

    FOR q IN SELECT * FROM shared.quota_thau
             WHERE nam_tai_chinh = k.o_fy AND ps = k.o_ps AND ma_khach_hang = k.o_cust
               AND nhom_san_pham = k.o_grp AND bo_vat_tu = k.o_mset AND san_pham = k.o_prod AND don_gia = k.o_gia
    LOOP
      -- Khoá đích đã có quota cùng loại × đợt → để lại
      IF EXISTS (SELECT 1 FROM shared.quota_thau x
                 WHERE x.nam_tai_chinh = k.n_fy AND x.ps = k.n_ps AND x.ma_khach_hang = k.n_cust
                   AND x.nhom_san_pham = k.n_grp AND x.bo_vat_tu = k.n_mset AND x.san_pham = k.n_prod
                   AND x.don_gia = k.n_gia AND x.loai = q.loai AND x.dot = q.dot) THEN
        INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
        VALUES ('giu_khoa_xung_dot', 'quota_thau', q.id, to_jsonb(q), to_jsonb(k));
        CONTINUE;
      END IF;
      -- Đổi nhóm: đợt mà quota tham chiếu phải có ở nhóm mới (chép nếu thiếu, khác tháng thì để lại)
      IF q.loai <> 'cu' AND (k.o_fy, k.o_ps, k.o_cust, k.o_grp) IS DISTINCT FROM (k.n_fy, k.n_ps, k.n_cust, k.n_grp) THEN
        SELECT * INTO v_dich FROM shared.dot_thau
        WHERE nam_tai_chinh = k.n_fy AND ps = k.n_ps AND ma_khach_hang = k.n_cust AND nhom_san_pham = k.n_grp
          AND loai = q.loai AND dot = q.dot;
        SELECT * INTO d FROM shared.dot_thau
        WHERE nam_tai_chinh = k.o_fy AND ps = k.o_ps AND ma_khach_hang = k.o_cust AND nhom_san_pham = k.o_grp
          AND loai = q.loai AND dot = q.dot;
        IF v_dich.id IS NULL THEN
          IF d.id IS NOT NULL THEN
            INSERT INTO shared.dot_thau (nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham, loai, dot,
                                         thang_thau, thoi_gian, updated_by, trang_thai, nguon)
            VALUES (k.n_fy, k.n_bu, k.n_mien, k.n_ps, k.n_cust, k.n_grp, q.loai, q.dot,
                    d.thang_thau, d.thoi_gian, 'giu_khoa', d.trang_thai, d.nguon);
          END IF;
        ELSIF d.id IS NOT NULL AND v_dich.thang_thau IS DISTINCT FROM d.thang_thau THEN
          INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
          VALUES ('giu_khoa_xung_dot', 'quota_thau', q.id, to_jsonb(q),
                  jsonb_build_object('khoa', to_jsonb(k), 'dot_cu', to_jsonb(d), 'dot_moi', to_jsonb(v_dich)));
          CONTINUE;
        END IF;
      END IF;

      UPDATE shared.quota_thau SET
        nam_tai_chinh = k.n_fy, ps = k.n_ps, ma_khach_hang = k.n_cust, nhom_san_pham = k.n_grp,
        bo_vat_tu = k.n_mset, san_pham = k.n_prod, don_gia = k.n_gia,
        bu = coalesce(k.n_bu, bu), mien = coalesce(k.n_mien, mien), khach_hang = coalesce(k.n_kh, khach_hang),
        updated_at = now(), updated_by = 'giu_khoa'
      WHERE id = q.id;
      INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
      SELECT 'giu_khoa', 'quota_thau', q.id, to_jsonb(q), to_jsonb(x) FROM shared.quota_thau x WHERE x.id = q.id;
    END LOOP;
  END LOOP;

  TRUNCATE _gk_doi;
  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION shared.ghi_doi_khoa_sale_target() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION shared.giu_khoa_quota_sale_target() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_sale_target_ghi_doi_khoa ON shared.sale_target;
CREATE TRIGGER trg_sale_target_ghi_doi_khoa
  AFTER UPDATE OF nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham, don_gia
  ON shared.sale_target
  FOR EACH ROW
  WHEN ((OLD.nam_tai_chinh, OLD.ps, OLD.ma_khach_hang, OLD.nhom_san_pham, OLD.bo_vat_tu, OLD.san_pham, OLD.don_gia)
        IS DISTINCT FROM
        (NEW.nam_tai_chinh, NEW.ps, NEW.ma_khach_hang, NEW.nhom_san_pham, NEW.bo_vat_tu, NEW.san_pham, NEW.don_gia))
  EXECUTE FUNCTION shared.ghi_doi_khoa_sale_target();

DROP TRIGGER IF EXISTS trg_sale_target_giu_khoa_quota ON shared.sale_target;
CREATE TRIGGER trg_sale_target_giu_khoa_quota
  AFTER UPDATE ON shared.sale_target
  FOR EACH STATEMENT EXECUTE FUNCTION shared.giu_khoa_quota_sale_target();

COMMIT;
