-- Khoá quota theo MÃ sản phẩm (quyết định của user 14/10): quota đi theo bệnh viện ×
-- sản phẩm × PS; sản phẩm nhận theo mã, mã thiếu / "Chưa có" thì theo tên, mã dùng
-- cho nhiều sản phẩm thì theo mã × tên.
--
-- App vẫn khớp quota với dòng kế hoạch theo tên (khoá text); P3 (20261015150000) giữ
-- tên đồng bộ khi dòng kế hoạch đổi khoá bằng UPDATE. Migration này bổ sung:
--   1. quota_thau.ma_san_pham: tự điền theo dòng kế hoạch cùng khoá (không có thì theo
--      dòng kế hoạch cùng tên, rồi theo danh mục dm_vat_tu / dm_bo_vat_tu); cập nhật
--      khi mã trên dòng kế hoạch đổi.
--   2. Gắn lại theo mã khi THÊM dòng kế hoạch (thêm SP, nạp kế hoạch): khoá mới chưa
--      có quota mà có đúng 1 khoá quota mồ côi (không còn dòng kế hoạch) cùng năm × PS
--      × KH × mã → chuyển quota sang khoá mới. Mã dùng cho nhiều tên → phải khớp cả tên.
--      Nhiều ứng viên → không chuyển, log 'gan_theo_ma_nhieu'.
--   3. Hàm chung shared.chuyen_quota_khoa() cho P3 và bước 2 (chép đợt khi đổi nhóm,
--      để lại + log khi khoá đích đã có quota / đợt cùng số khác tháng).

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Mã sản phẩm trên quota_thau
-- ---------------------------------------------------------------------------
ALTER TABLE shared.quota_thau ADD COLUMN IF NOT EXISTS ma_san_pham text;
COMMENT ON COLUMN shared.quota_thau.ma_san_pham IS
  'Mã SP (theo dòng kế hoạch cùng khoá, không có thì theo danh mục). Dùng để gắn lại quota mồ côi theo mã.';

CREATE OR REPLACE FUNCTION shared.ma_sp_hop_le(v text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN nullif(btrim(v), '') IS NULL OR v ~* '^ch.a c' THEN NULL ELSE btrim(v) END;
$$;

CREATE OR REPLACE FUNCTION shared.ten_sp_chuan(v text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT lower(regexp_replace(btrim(coalesce(v, '')), '\s+', ' ', 'g'));
$$;

CREATE OR REPLACE FUNCTION shared.ma_sp_cua_khoa(p_fy text, p_ps text, p_cust text, p_grp text,
                                                 p_mset text, p_prod text, p_gia numeric)
RETURNS text LANGUAGE sql STABLE SET search_path = shared, public AS $$
  SELECT coalesce(
    (SELECT min(shared.ma_sp_hop_le(s.ma_san_pham)) FROM shared.sale_target s
     WHERE s.ps = p_ps AND s.nam_tai_chinh = p_fy AND coalesce(s.ma_khach_hang,'') = p_cust
       AND coalesce(s.nhom_san_pham,'') = p_grp AND coalesce(s.bo_vat_tu,'') = p_mset
       AND coalesce(s.san_pham,'') = p_prod AND coalesce(s.don_gia,0) = p_gia),
    (SELECT CASE WHEN count(DISTINCT shared.ma_sp_hop_le(s.ma_san_pham)) = 1
                 THEN min(shared.ma_sp_hop_le(s.ma_san_pham)) END
     FROM shared.sale_target s
     WHERE shared.ten_sp_chuan(s.san_pham) = shared.ten_sp_chuan(p_prod)),
    (SELECT CASE WHEN count(DISTINCT shared.ma_sp_hop_le(v.ma_san_pham)) = 1
                 THEN min(shared.ma_sp_hop_le(v.ma_san_pham)) END
     FROM shared.dm_vat_tu v WHERE shared.ten_sp_chuan(v.san_pham) = shared.ten_sp_chuan(p_prod)),
    (SELECT CASE WHEN count(DISTINCT b.ma_bo_vat_tu) = 1 THEN min(b.ma_bo_vat_tu) END
     FROM shared.dm_bo_vat_tu b WHERE shared.ten_sp_chuan(b.bo_vat_tu) = shared.ten_sp_chuan(p_prod)));
$$;

CREATE OR REPLACE FUNCTION shared.trg_quota_thau_ma_sp()
RETURNS trigger LANGUAGE plpgsql SET search_path = shared, public AS $$
BEGIN
  NEW.ma_san_pham := coalesce(
    shared.ma_sp_cua_khoa(NEW.nam_tai_chinh, NEW.ps, NEW.ma_khach_hang, NEW.nhom_san_pham,
                          NEW.bo_vat_tu, NEW.san_pham, NEW.don_gia),
    NEW.ma_san_pham);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_quota_thau_ma_sp ON shared.quota_thau;
CREATE TRIGGER trg_quota_thau_ma_sp
  BEFORE INSERT OR UPDATE OF nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu, san_pham, don_gia
  ON shared.quota_thau
  FOR EACH ROW EXECUTE FUNCTION shared.trg_quota_thau_ma_sp();

-- Dò mã theo tên chuẩn hoá (khi khoá không còn dòng kế hoạch) — cần index để không quét cả bảng.
CREATE INDEX IF NOT EXISTS idx_sale_target_ten_sp_chuan ON shared.sale_target (shared.ten_sp_chuan(san_pham));
CREATE INDEX IF NOT EXISTS idx_dm_vat_tu_ten_sp_chuan ON shared.dm_vat_tu (shared.ten_sp_chuan(san_pham));
CREATE INDEX IF NOT EXISTS idx_dm_bo_vat_tu_ten_sp_chuan ON shared.dm_bo_vat_tu (shared.ten_sp_chuan(bo_vat_tu));

UPDATE shared.quota_thau q
SET ma_san_pham = shared.ma_sp_cua_khoa(q.nam_tai_chinh, q.ps, q.ma_khach_hang, q.nhom_san_pham,
                                        q.bo_vat_tu, q.san_pham, q.don_gia);

-- Mã trên dòng kế hoạch đổi (vd resync theo danh mục) → mã của quota cùng khoá đổi theo
CREATE OR REPLACE FUNCTION shared.trg_sale_target_ma_sp_quota()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = shared, public AS $$
BEGIN
  IF shared.ma_sp_hop_le(NEW.ma_san_pham) IS NOT NULL AND NOT coalesce(NEW.ngoai_ke_hoach, false) THEN
    UPDATE shared.quota_thau q SET ma_san_pham = shared.ma_sp_hop_le(NEW.ma_san_pham)
    WHERE q.nam_tai_chinh = NEW.nam_tai_chinh AND q.ps = coalesce(NEW.ps,'')
      AND q.ma_khach_hang = coalesce(NEW.ma_khach_hang,'') AND q.nhom_san_pham = coalesce(NEW.nhom_san_pham,'')
      AND q.bo_vat_tu = coalesce(NEW.bo_vat_tu,'') AND q.san_pham = coalesce(NEW.san_pham,'')
      AND q.don_gia = coalesce(NEW.don_gia,0)
      AND q.ma_san_pham IS DISTINCT FROM shared.ma_sp_hop_le(NEW.ma_san_pham);
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION shared.trg_sale_target_ma_sp_quota() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_sale_target_ma_sp_quota ON shared.sale_target;
CREATE TRIGGER trg_sale_target_ma_sp_quota
  AFTER UPDATE OF ma_san_pham ON shared.sale_target
  FOR EACH ROW WHEN (OLD.ma_san_pham IS DISTINCT FROM NEW.ma_san_pham)
  EXECUTE FUNCTION shared.trg_sale_target_ma_sp_quota();

-- ---------------------------------------------------------------------------
-- 3. Hàm chung chuyển quota từ khoá cũ sang khoá mới
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION shared.chuyen_quota_khoa(
  o_fy text, o_ps text, o_cust text, o_grp text, o_mset text, o_prod text, o_gia numeric,
  n_fy text, n_ps text, n_cust text, n_grp text, n_mset text, n_prod text, n_gia numeric,
  n_bu text, n_mien text, n_kh text, p_buoc text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = shared, public
AS $$
DECLARE
  q record;
  d record;
  v_dich record;
  v_n int := 0;
  v_khoa jsonb := jsonb_build_object(
    'tu', jsonb_build_array(o_fy, o_ps, o_cust, o_grp, o_mset, o_prod, o_gia),
    'den', jsonb_build_array(n_fy, n_ps, n_cust, n_grp, n_mset, n_prod, n_gia));
BEGIN
  FOR q IN SELECT * FROM shared.quota_thau
           WHERE nam_tai_chinh = o_fy AND ps = o_ps AND ma_khach_hang = o_cust
             AND nhom_san_pham = o_grp AND bo_vat_tu = o_mset AND san_pham = o_prod AND don_gia = o_gia
  LOOP
    -- Khoá đích đã có quota cùng loại × đợt → để lại
    IF EXISTS (SELECT 1 FROM shared.quota_thau x
               WHERE x.nam_tai_chinh = n_fy AND x.ps = n_ps AND x.ma_khach_hang = n_cust
                 AND x.nhom_san_pham = n_grp AND x.bo_vat_tu = n_mset AND x.san_pham = n_prod
                 AND x.don_gia = n_gia AND x.loai = q.loai AND x.dot = q.dot) THEN
      INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
      VALUES (p_buoc || '_xung_dot', 'quota_thau', q.id, to_jsonb(q), v_khoa);
      CONTINUE;
    END IF;
    -- Đổi nhóm: đợt quota tham chiếu phải có ở nhóm mới (chép nếu thiếu, khác tháng thì để lại)
    IF q.loai <> 'cu' AND (o_fy, o_ps, o_cust, o_grp) IS DISTINCT FROM (n_fy, n_ps, n_cust, n_grp) THEN
      v_dich := NULL;
      d := NULL;
      SELECT * INTO v_dich FROM shared.dot_thau
      WHERE nam_tai_chinh = n_fy AND ps = n_ps AND ma_khach_hang = n_cust AND nhom_san_pham = n_grp
        AND loai = q.loai AND dot = q.dot;
      SELECT * INTO d FROM shared.dot_thau
      WHERE nam_tai_chinh = o_fy AND ps = o_ps AND ma_khach_hang = o_cust AND nhom_san_pham = o_grp
        AND loai = q.loai AND dot = q.dot;
      IF v_dich.id IS NULL THEN
        IF d.id IS NOT NULL THEN
          INSERT INTO shared.dot_thau (nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham, loai, dot,
                                       thang_thau, thoi_gian, updated_by, trang_thai, nguon)
          VALUES (n_fy, n_bu, n_mien, n_ps, n_cust, n_grp, q.loai, q.dot,
                  d.thang_thau, d.thoi_gian, p_buoc, d.trang_thai, d.nguon);
        END IF;
      ELSIF d.id IS NOT NULL AND v_dich.thang_thau IS DISTINCT FROM d.thang_thau THEN
        INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
        VALUES (p_buoc || '_xung_dot', 'quota_thau', q.id, to_jsonb(q),
                v_khoa || jsonb_build_object('dot_cu', to_jsonb(d), 'dot_moi', to_jsonb(v_dich)));
        CONTINUE;
      END IF;
    END IF;

    UPDATE shared.quota_thau SET
      nam_tai_chinh = n_fy, ps = n_ps, ma_khach_hang = n_cust, nhom_san_pham = n_grp,
      bo_vat_tu = n_mset, san_pham = n_prod, don_gia = n_gia,
      bu = coalesce(n_bu, bu), mien = coalesce(n_mien, mien), khach_hang = coalesce(n_kh, khach_hang),
      updated_at = now(), updated_by = p_buoc
    WHERE id = q.id;
    INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
    SELECT p_buoc, 'quota_thau', q.id, to_jsonb(q), to_jsonb(x) FROM shared.quota_thau x WHERE x.id = q.id;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;
REVOKE ALL ON FUNCTION shared.chuyen_quota_khoa(text, text, text, text, text, text, numeric,
  text, text, text, text, text, text, numeric, text, text, text, text) FROM PUBLIC, anon, authenticated;

-- P3 dùng hàm chung (hành vi giữ nguyên)
CREATE OR REPLACE FUNCTION shared.giu_khoa_quota_sale_target()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = shared, public
AS $$
DECLARE
  g record;
  k record;
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
    PERFORM shared.chuyen_quota_khoa(k.o_fy, k.o_ps, k.o_cust, k.o_grp, k.o_mset, k.o_prod, k.o_gia,
                                     k.n_fy, k.n_ps, k.n_cust, k.n_grp, k.n_mset, k.n_prod, k.n_gia,
                                     k.n_bu, k.n_mien, k.n_kh, 'giu_khoa');
  END LOOP;

  TRUNCATE _gk_doi;
  RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Gắn lại quota mồ côi theo mã khi thêm dòng kế hoạch
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION shared.ghi_khoa_moi_sale_target()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = shared, public AS $$
BEGIN
  IF to_regclass('pg_temp._gk_moi') IS NULL THEN
    CREATE TEMP TABLE _gk_moi (
      fy text, ps text, cust text, grp text, mset text, prod text, gia numeric,
      ma text, bu text, mien text, kh text
    ) ON COMMIT DROP;
  END IF;
  INSERT INTO _gk_moi VALUES (
    NEW.nam_tai_chinh, coalesce(NEW.ps,''), coalesce(NEW.ma_khach_hang,''), coalesce(NEW.nhom_san_pham,''),
    coalesce(NEW.bo_vat_tu,''), coalesce(NEW.san_pham,''), coalesce(NEW.don_gia,0),
    shared.ma_sp_hop_le(NEW.ma_san_pham), NEW.bu, NEW.mien, NEW.khach_hang);
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION shared.gan_quota_theo_ma_sale_target()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = shared, public AS $$
DECLARE
  m record;
  c record;
  v_nhieu_ten boolean;
  v_n int;
BEGIN
  IF to_regclass('pg_temp._gk_moi') IS NULL THEN
    RETURN NULL;
  END IF;
  FOR m IN
    SELECT DISTINCT ON (fy, ps, cust, grp, mset, prod, gia) * FROM _gk_moi
    WHERE ma IS NOT NULL
    ORDER BY fy, ps, cust, grp, mset, prod, gia
  LOOP
    -- Khoá mới đã có quota → không cần gắn
    CONTINUE WHEN EXISTS (SELECT 1 FROM shared.quota_thau q
                          WHERE q.nam_tai_chinh = m.fy AND q.ps = m.ps AND q.ma_khach_hang = m.cust
                            AND q.nhom_san_pham = m.grp AND q.bo_vat_tu = m.mset AND q.san_pham = m.prod
                            AND q.don_gia = m.gia);
    -- Lọc nhanh: không có quota nào cùng năm × PS × KH × mã thì thôi
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM shared.quota_thau q
                              WHERE q.nam_tai_chinh = m.fy AND q.ps = m.ps AND q.ma_khach_hang = m.cust
                                AND q.ma_san_pham = m.ma);
    -- Mã dùng cho nhiều SP → phải khớp cả tên. Không đếm tên mới: SP vừa đổi tên vẫn
    -- còn tên cũ ở PS / KH khác, không vì thế mà coi mã là dùng chung.
    SELECT count(DISTINCT shared.ten_sp_chuan(s.san_pham)) > 1 INTO v_nhieu_ten
    FROM shared.sale_target s
    WHERE shared.ma_sp_hop_le(s.ma_san_pham) = m.ma
      AND shared.ten_sp_chuan(s.san_pham) <> shared.ten_sp_chuan(m.prod);

    -- Ứng viên: khoá quota mồ côi cùng năm × PS × KH × mã
    SELECT count(*) n, min(nam_tai_chinh) fy, min(ps) ps, min(ma_khach_hang) cust, min(nhom_san_pham) grp,
           min(bo_vat_tu) mset, min(san_pham) prod, min(don_gia) gia
      INTO c
    FROM (
      SELECT DISTINCT q.nam_tai_chinh, q.ps, q.ma_khach_hang, q.nhom_san_pham, q.bo_vat_tu, q.san_pham, q.don_gia
      FROM shared.quota_thau q
      WHERE q.nam_tai_chinh = m.fy AND q.ps = m.ps AND q.ma_khach_hang = m.cust
        AND q.ma_san_pham = m.ma
        AND (NOT v_nhieu_ten OR shared.ten_sp_chuan(q.san_pham) = shared.ten_sp_chuan(m.prod))
        AND NOT EXISTS (SELECT 1 FROM shared.sale_target s
                        WHERE s.nam_tai_chinh = q.nam_tai_chinh AND coalesce(s.ps,'') = q.ps
                          AND coalesce(s.ma_khach_hang,'') = q.ma_khach_hang AND coalesce(s.nhom_san_pham,'') = q.nhom_san_pham
                          AND coalesce(s.bo_vat_tu,'') = q.bo_vat_tu AND coalesce(s.san_pham,'') = q.san_pham
                          AND coalesce(s.don_gia,0) = q.don_gia AND NOT coalesce(s.ngoai_ke_hoach, false))
    ) u;

    IF c.n = 1 THEN
      v_n := shared.chuyen_quota_khoa(c.fy, c.ps, c.cust, c.grp, c.mset, c.prod, c.gia,
                                      m.fy, m.ps, m.cust, m.grp, m.mset, m.prod, m.gia,
                                      m.bu, m.mien, m.kh, 'gan_theo_ma');
    ELSIF c.n > 1 THEN
      INSERT INTO shared.quota_chuan_hoa_log (buoc, bang, truoc, sau)
      VALUES ('gan_theo_ma_nhieu', 'quota_thau', to_jsonb(m), jsonb_build_object('so_ung_vien', c.n));
    END IF;
  END LOOP;
  TRUNCATE _gk_moi;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION shared.ghi_khoa_moi_sale_target() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION shared.gan_quota_theo_ma_sale_target() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_sale_target_ghi_khoa_moi ON shared.sale_target;
CREATE TRIGGER trg_sale_target_ghi_khoa_moi
  AFTER INSERT ON shared.sale_target
  FOR EACH ROW WHEN (NOT coalesce(NEW.ngoai_ke_hoach, false))
  EXECUTE FUNCTION shared.ghi_khoa_moi_sale_target();

DROP TRIGGER IF EXISTS trg_sale_target_gan_quota_theo_ma ON shared.sale_target;
CREATE TRIGGER trg_sale_target_gan_quota_theo_ma
  AFTER INSERT ON shared.sale_target
  FOR EACH STATEMENT EXECUTE FUNCTION shared.gan_quota_theo_ma_sale_target();

COMMIT;
