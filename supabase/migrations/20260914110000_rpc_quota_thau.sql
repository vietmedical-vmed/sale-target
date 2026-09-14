-- RPC ghi đợt thầu và quota thầu trên 2 bảng shared.dot_thau / shared.quota_thau.
--
-- Cùng mô hình quyền với public.update_sale_target_cells: edge function gọi
-- bằng service_role và truyền xuống phạm vi của user (bu / mien / ps / groups).
-- Hàm tự kiểm tra phạm vi, sai thì RAISE 42501 chứ không ghi im lặng.
--
-- Phạm vi được xác thực qua chính shared.sale_target: nhóm SP muốn ghi phải
-- tồn tại trong sale_target và nằm trong phạm vi của user. Nhờ vậy bu / mien
-- lấy được luôn từ đó, không cần client gửi lên (client không được phép tự
-- khai bu — đó là ranh giới phân quyền giữa các team).

-- ---------------------------------------------------------------------------
-- Helper: nhóm SP có nằm trong phạm vi user không, và bu/mien của nó là gì.
-- Trả 0 dòng nếu ngoài phạm vi hoặc nhóm không tồn tại.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION shared.scope_nhom_sp(
  p_fy      text,
  p_ps      text,
  p_cust    text,
  p_grp     text,
  p_bu      text,
  p_mien    text,
  p_ps_lock text,
  p_groups  text[]
)
RETURNS TABLE (bu text, mien text)
LANGUAGE sql
STABLE
SET search_path = shared, public
AS $$
  SELECT min(s.bu), min(s.mien)
  FROM   shared.sale_target s
  WHERE  s.nam_tai_chinh = p_fy
    AND  s.ps            = p_ps
    AND  coalesce(s.ma_khach_hang, '') = coalesce(p_cust, '')
    AND  coalesce(s.nhom_san_pham, '') = coalesce(p_grp, '')
    AND  (p_bu      IS NULL OR s.bu            =     p_bu)
    AND  (p_mien    IS NULL OR s.mien          =     p_mien)
    AND  (p_ps_lock IS NULL OR s.ps            =     p_ps_lock)
    AND  (p_groups  IS NULL OR s.nhom_san_pham = ANY(p_groups))
  HAVING count(*) > 0;
$$;

-- ---------------------------------------------------------------------------
-- 1. Ghi đợt thầu (thêm mới hoặc sửa tháng / thời gian).
--
-- p_rows: [{ fy, ps, custId, grp, loai, dot, thang, thoiGian }]
--   * dot NULL  -> thêm đợt mới, tự lấy số kế tiếp trong cùng (nhóm, loai).
--   * dot có số -> sửa đợt đang có; đợt không tồn tại thì tạo đúng số đó.
--   * thang NULL hoặc '' -> để trống, hợp lệ (đợt đã biết nhưng chưa rõ tháng).
-- Trả số dòng đã ghi.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_dot_thau(
  p_rows   jsonb,
  p_bu     text,
  p_mien   text,
  p_ps     text,
  p_groups text[],
  p_actor  text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, shared
AS $$
DECLARE
  r      jsonb;
  v_bu   text;
  v_mien text;
  v_fy   text;
  v_ps   text;
  v_cust text;
  v_grp  text;
  v_loai text;
  v_dot  int;
  v_thang text;
  v_done int := 0;
BEGIN
  FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  LOOP
    v_fy   := r->>'fy';
    v_ps   := r->>'ps';
    v_cust := coalesce(r->>'custId', '');
    v_grp  := coalesce(r->>'grp', '');
    v_loai := r->>'loai';
    v_thang := nullif(r->>'thang', '');

    IF v_loai NOT IN ('chinh', 'bo_sung') THEN
      RAISE EXCEPTION 'loai_khong_hop_le: %', v_loai USING ERRCODE = '22023';
    END IF;
    IF v_thang IS NOT NULL AND v_thang !~ '^\d{4}-\d{2}$' THEN
      RAISE EXCEPTION 'thang_sai_dinh_dang: % (cần yyyy-mm)', v_thang USING ERRCODE = '22023';
    END IF;

    SELECT s.bu, s.mien INTO v_bu, v_mien
    FROM shared.scope_nhom_sp(v_fy, v_ps, v_cust, v_grp, p_bu, p_mien, p_ps, p_groups) s;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'out_of_scope: nhóm % / KH % / PS % nằm ngoài phạm vi quyền hoặc không tồn tại',
                      v_grp, v_cust, v_ps USING ERRCODE = '42501';
    END IF;

    v_dot := nullif(r->>'dot', '')::int;
    IF v_dot IS NULL THEN
      SELECT coalesce(max(d.dot), 0) + 1 INTO v_dot
      FROM   shared.dot_thau d
      WHERE  d.nam_tai_chinh = v_fy AND d.ps = v_ps
        AND  d.ma_khach_hang = v_cust AND d.nhom_san_pham = v_grp
        AND  d.loai = v_loai;
    END IF;

    INSERT INTO shared.dot_thau
      (nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham,
       loai, dot, thang_thau, thoi_gian, updated_by)
    VALUES
      (v_fy, v_bu, v_mien, v_ps, v_cust, v_grp,
       v_loai, v_dot, v_thang, nullif(r->>'thoiGian', '')::numeric, p_actor)
    ON CONFLICT (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, loai, dot)
    DO UPDATE SET
      thang_thau = EXCLUDED.thang_thau,
      thoi_gian  = CASE WHEN r ? 'thoiGian' THEN EXCLUDED.thoi_gian
                        ELSE shared.dot_thau.thoi_gian END,
      updated_at = now(),
      updated_by = p_actor;

    v_done := v_done + 1;
  END LOOP;

  RETURN v_done;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Xoá 1 đợt thầu, kèm toàn bộ quota thuộc đợt đó.
--    KHÔNG đánh số lại các đợt còn lại: số đợt là nhãn ổn định, đánh lại sẽ
--    làm lệch mọi tham chiếu đang mở trên máy người khác. Chấp nhận có lỗ
--    (1, 3, 4) và để UI sắp xếp theo tháng.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_dot_thau(
  p_fy     text,
  p_ps_row text,
  p_cust   text,
  p_grp    text,
  p_loai   text,
  p_dot    int,
  p_bu     text,
  p_mien   text,
  p_ps     text,
  p_groups text[]
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, shared
AS $$
DECLARE
  v_cust text := coalesce(p_cust, '');
  v_grp  text := coalesce(p_grp, '');
  v_n    int;
BEGIN
  PERFORM 1 FROM shared.scope_nhom_sp(p_fy, p_ps_row, v_cust, v_grp,
                                      p_bu, p_mien, p_ps, p_groups);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'out_of_scope: nhóm % / KH % / PS % nằm ngoài phạm vi quyền hoặc không tồn tại',
                    v_grp, v_cust, p_ps_row USING ERRCODE = '42501';
  END IF;

  DELETE FROM shared.quota_thau q
  WHERE q.nam_tai_chinh = p_fy AND q.ps = p_ps_row
    AND q.ma_khach_hang = v_cust AND q.nhom_san_pham = v_grp
    AND q.loai = p_loai AND q.dot = p_dot;

  DELETE FROM shared.dot_thau d
  WHERE d.nam_tai_chinh = p_fy AND d.ps = p_ps_row
    AND d.ma_khach_hang = v_cust AND d.nhom_san_pham = v_grp
    AND d.loai = p_loai AND d.dot = p_dot;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Ghi quota thầu theo sản phẩm x mức giá x đợt.
--
-- p_rows: [{ fy, ps, custId, grp, mset, prod, price, loai, dot, qty }]
--   * qty NULL / '' / 0 -> xoá dòng quota đó (không giữ dòng 0 cho rác).
--   * loai = 'cu' thì dot luôn là 1 (quota thầu cũ không thuộc đợt nào).
--   * loai 'chinh' / 'bo_sung' bắt buộc đợt phải tồn tại trong dot_thau.
-- Trả số dòng đã ghi hoặc xoá.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_quota_thau(
  p_rows   jsonb,
  p_bu     text,
  p_mien   text,
  p_ps     text,
  p_groups text[],
  p_actor  text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, shared
AS $$
DECLARE
  r       jsonb;
  v_bu    text;
  v_mien  text;
  v_fy    text;
  v_ps    text;
  v_cust  text;
  v_grp   text;
  v_mset  text;
  v_prod  text;
  v_price numeric;
  v_loai  text;
  v_dot   int;
  v_qty   numeric;
  v_done  int := 0;
BEGIN
  FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  LOOP
    v_fy    := r->>'fy';
    v_ps    := r->>'ps';
    v_cust  := coalesce(r->>'custId', '');
    v_grp   := coalesce(r->>'grp', '');
    v_mset  := coalesce(r->>'mset', '');
    v_prod  := coalesce(r->>'prod', '');
    v_price := coalesce(nullif(r->>'price', '')::numeric, 0);
    v_loai  := r->>'loai';
    v_qty   := nullif(r->>'qty', '')::numeric;

    IF v_loai NOT IN ('cu', 'chinh', 'bo_sung') THEN
      RAISE EXCEPTION 'loai_khong_hop_le: %', v_loai USING ERRCODE = '22023';
    END IF;

    SELECT s.bu, s.mien INTO v_bu, v_mien
    FROM shared.scope_nhom_sp(v_fy, v_ps, v_cust, v_grp, p_bu, p_mien, p_ps, p_groups) s;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'out_of_scope: nhóm % / KH % / PS % nằm ngoài phạm vi quyền hoặc không tồn tại',
                      v_grp, v_cust, v_ps USING ERRCODE = '42501';
    END IF;

    IF v_loai = 'cu' THEN
      v_dot := 1;
    ELSE
      v_dot := coalesce(nullif(r->>'dot', '')::int, 1);
      PERFORM 1 FROM shared.dot_thau d
       WHERE d.nam_tai_chinh = v_fy AND d.ps = v_ps
         AND d.ma_khach_hang = v_cust AND d.nhom_san_pham = v_grp
         AND d.loai = v_loai AND d.dot = v_dot;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'dot_khong_ton_tai: % đợt % của nhóm % — tạo đợt trước khi nhập quota',
                        v_loai, v_dot, v_grp USING ERRCODE = '23503';
      END IF;
    END IF;

    IF v_qty IS NULL OR v_qty = 0 THEN
      DELETE FROM shared.quota_thau q
      WHERE q.nam_tai_chinh = v_fy AND q.ps = v_ps
        AND q.ma_khach_hang = v_cust AND q.nhom_san_pham = v_grp
        AND q.bo_vat_tu = v_mset AND q.san_pham = v_prod
        AND q.don_gia = v_price AND q.loai = v_loai AND q.dot = v_dot;
    ELSE
      INSERT INTO shared.quota_thau
        (nam_tai_chinh, bu, mien, ps, ma_khach_hang, khach_hang, nhom_san_pham,
         bo_vat_tu, san_pham, don_gia, loai, dot, so_luong, updated_by)
      VALUES
        (v_fy, v_bu, v_mien, v_ps, v_cust, nullif(r->>'cust', ''), v_grp,
         v_mset, v_prod, v_price, v_loai, v_dot, v_qty, p_actor)
      ON CONFLICT (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, bo_vat_tu,
                   san_pham, don_gia, loai, dot)
      DO UPDATE SET
        so_luong   = EXCLUDED.so_luong,
        khach_hang = coalesce(EXCLUDED.khach_hang, shared.quota_thau.khach_hang),
        updated_at = now(),
        updated_by = p_actor;
    END IF;

    v_done := v_done + 1;
  END LOOP;

  RETURN v_done;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Đọc đợt thầu + quota theo phạm vi, cho getData.
--    Trả dạng phẳng để edge function map thẳng sang JSON.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_quota_thau(
  p_fy     text,
  p_bu     text,
  p_mien   text,
  p_ps     text,
  p_groups text[]
)
RETURNS TABLE (
  kind      text,      -- 'dot' | 'quota'
  fy        text,
  ps        text,
  cust_id   text,
  grp       text,
  mset      text,
  prod      text,
  price     numeric,
  loai      text,
  dot       int,
  thang     text,
  thoi_gian numeric,
  qty       numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, shared
AS $$
  SELECT 'dot', d.nam_tai_chinh, d.ps, d.ma_khach_hang, d.nhom_san_pham,
         NULL, NULL, NULL, d.loai, d.dot, d.thang_thau, d.thoi_gian, NULL
  FROM   shared.dot_thau d
  WHERE  (p_fy     IS NULL OR d.nam_tai_chinh = p_fy)
    AND  (p_bu     IS NULL OR d.bu            =     p_bu)
    AND  (p_mien   IS NULL OR d.mien          =     p_mien)
    AND  (p_ps     IS NULL OR d.ps            =     p_ps)
    AND  (p_groups IS NULL OR d.nhom_san_pham = ANY(p_groups))
  UNION ALL
  SELECT 'quota', q.nam_tai_chinh, q.ps, q.ma_khach_hang, q.nhom_san_pham,
         q.bo_vat_tu, q.san_pham, q.don_gia, q.loai, q.dot, NULL, NULL, q.so_luong
  FROM   shared.quota_thau q
  WHERE  (p_fy     IS NULL OR q.nam_tai_chinh = p_fy)
    AND  (p_bu     IS NULL OR q.bu            =     p_bu)
    AND  (p_mien   IS NULL OR q.mien          =     p_mien)
    AND  (p_ps     IS NULL OR q.ps            =     p_ps)
    AND  (p_groups IS NULL OR q.nhom_san_pham = ANY(p_groups));
$$;

-- ---------------------------------------------------------------------------
-- 5. Quyền: chỉ edge function (service_role) được gọi.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.upsert_dot_thau(jsonb, text, text, text, text[], text)   FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.upsert_quota_thau(jsonb, text, text, text, text[], text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.delete_dot_thau(text, text, text, text, text, int, text, text, text, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_quota_thau(text, text, text, text, text[])           FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION shared.scope_nhom_sp(text, text, text, text, text, text, text, text[]) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.upsert_dot_thau(jsonb, text, text, text, text[], text)   TO service_role;
GRANT EXECUTE ON FUNCTION public.upsert_quota_thau(jsonb, text, text, text, text[], text) TO service_role;
GRANT EXECUTE ON FUNCTION public.delete_dot_thau(text, text, text, text, text, int, text, text, text, text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_quota_thau(text, text, text, text, text[])           TO service_role;
