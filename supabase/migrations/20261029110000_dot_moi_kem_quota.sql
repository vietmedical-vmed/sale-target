-- Đợt thầu mới phải đi cùng quota: không còn tạo đợt rỗng.
--
-- Trước đây đợt tạo riêng ở đầu nhóm SP (saveDotThau) rồi mới nhập quota, nên đợt
-- không quota cứ thế nằm lại — 29/10 vừa xoá 134 đợt mồ côi (20261029100000).
-- Từ nay:
--   * public.luu_quota_thau lưu đợt mới + quota trong MỘT giao dịch; đợt mới phải
--     có tháng thầu, hiệu lực (kiểm ở upsert_dot_thau) và ít nhất 1 quota > 0.
--   * Đợt nào bị chạm trong lần lưu mà không còn quota > 0 → từ chối (muốn bỏ thì
--     xoá đợt; delete_dot_thau xoá luôn quota).
--   * upsert_dot_thau chỉ tạo đợt mới khi được gọi từ luu_quota_thau (cờ giao dịch
--     app.cho_tao_dot); gọi thẳng chỉ sửa tháng / hiệu lực đợt đã có.

BEGIN;

CREATE OR REPLACE FUNCTION public.upsert_dot_thau(p_rows jsonb, p_bu text, p_mien text, p_ps text, p_groups text[], p_actor text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared'
AS $function$
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
  v_tg   numeric;
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

    -- Đợt mới chỉ tạo cùng quota (qua luu_quota_thau), không tạo đợt rỗng.
    IF coalesce(current_setting('app.cho_tao_dot', true), '') <> '1' AND NOT EXISTS (
         SELECT 1 FROM shared.dot_thau d
         WHERE d.nam_tai_chinh = v_fy AND d.ps = v_ps AND d.ma_khach_hang = v_cust
           AND d.nhom_san_pham = v_grp AND d.loai = v_loai AND d.dot = v_dot) THEN
      RAISE EXCEPTION 'dot_moi_phai_kem_quota: thêm đợt trong bảng nhập quota, điền tháng thầu, hiệu lực và quota rồi lưu một lần'
        USING ERRCODE = '22023';
    END IF;

    -- Bắt buộc tháng thầu + hiệu lực (số tháng). Không gửi thoiGian = giữ hiệu lực đang có.
    IF r ? 'thoiGian' THEN
      v_tg := nullif(r->>'thoiGian', '')::numeric;
    ELSE
      SELECT d.thoi_gian INTO v_tg FROM shared.dot_thau d
      WHERE d.nam_tai_chinh = v_fy AND d.ps = v_ps AND d.ma_khach_hang = v_cust
        AND d.nhom_san_pham = v_grp AND d.loai = v_loai AND d.dot = v_dot;
    END IF;
    IF v_thang IS NULL THEN
      RAISE EXCEPTION 'dot_thieu_thong_tin: đợt thầu phải có tháng thầu (yyyy-mm)' USING ERRCODE = '22023';
    END IF;
    IF v_tg IS NULL OR v_tg <= 0 OR v_tg > 120 OR v_tg <> trunc(v_tg) THEN
      RAISE EXCEPTION 'dot_thieu_thong_tin: đợt thầu phải có hiệu lực (số tháng nguyên, 1–120)' USING ERRCODE = '22023';
    END IF;

    INSERT INTO shared.dot_thau
      (nam_tai_chinh, bu, mien, ps, ma_khach_hang, nhom_san_pham,
       loai, dot, thang_thau, thoi_gian, updated_by)
    VALUES
      (v_fy, v_bu, v_mien, v_ps, v_cust, v_grp,
       v_loai, v_dot, v_thang, v_tg, p_actor)
    ON CONFLICT (nam_tai_chinh, ps, ma_khach_hang, nhom_san_pham, loai, dot)
    DO UPDATE SET
      trang_thai = 'chinh_thuc',
      thang_thau = EXCLUDED.thang_thau,
      thoi_gian  = EXCLUDED.thoi_gian,
      updated_at = now(),
      updated_by = p_actor;

    v_done := v_done + 1;
  END LOOP;

  RETURN v_done;
END;
$function$;

CREATE OR REPLACE FUNCTION public.luu_quota_thau(p_dots jsonb, p_rows jsonb, p_bu text, p_mien text, p_ps text, p_groups text[], p_actor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'shared'
AS $function$
DECLARE
  r         jsonb;
  k         record;
  v_n_dot   int := 0;
  v_n_quota int := 0;
BEGIN
  -- Đợt mới: client đánh số (max + 1) để quota cùng lô trỏ đúng đợt; trùng số nghĩa là
  -- người khác vừa thêm đợt → bắt tải lại thay vì ghi đè tháng của họ.
  FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_dots, '[]'::jsonb))
  LOOP
    IF nullif(r->>'dot', '') IS NULL THEN
      RAISE EXCEPTION 'dot_moi_thieu_so: đợt mới phải có số đợt' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
         SELECT 1 FROM shared.dot_thau d
         WHERE d.nam_tai_chinh = r->>'fy' AND d.ps = r->>'ps'
           AND d.ma_khach_hang = coalesce(r->>'custId', '') AND d.nhom_san_pham = coalesce(r->>'grp', '')
           AND d.loai = r->>'loai' AND d.dot = (r->>'dot')::int) THEN
      RAISE EXCEPTION 'dot_da_ton_tai: nhóm % vừa có người thêm đợt — tải lại rồi nhập lại', r->>'grp'
        USING ERRCODE = '23505';
    END IF;
  END LOOP;

  IF jsonb_array_length(coalesce(p_dots, '[]'::jsonb)) > 0 THEN
    PERFORM set_config('app.cho_tao_dot', '1', true);
    v_n_dot := public.upsert_dot_thau(p_dots, p_bu, p_mien, p_ps, p_groups, p_actor);
    PERFORM set_config('app.cho_tao_dot', '', true);
  END IF;

  IF jsonb_array_length(coalesce(p_rows, '[]'::jsonb)) > 0 THEN
    v_n_quota := public.upsert_quota_thau(p_rows, p_bu, p_mien, p_ps, p_groups, p_actor);
  END IF;

  -- Mọi đợt chạm tới trong lần lưu phải còn ít nhất 1 quota > 0 (giá trị thầu).
  FOR k IN
    SELECT DISTINCT x->>'fy' AS fy, x->>'ps' AS ps, coalesce(x->>'custId', '') AS cust,
           coalesce(x->>'grp', '') AS grp, x->>'loai' AS loai,
           coalesce(nullif(x->>'dot', '')::int, 1) AS dot
    FROM jsonb_array_elements(coalesce(p_dots, '[]'::jsonb) || coalesce(p_rows, '[]'::jsonb)) x
    WHERE x->>'loai' IN ('chinh', 'bo_sung')
  LOOP
    IF EXISTS (
         SELECT 1 FROM shared.dot_thau d
         WHERE d.nam_tai_chinh = k.fy AND d.ps = k.ps AND d.ma_khach_hang = k.cust
           AND d.nhom_san_pham = k.grp AND d.loai = k.loai AND d.dot = k.dot)
       AND NOT EXISTS (
         SELECT 1 FROM shared.quota_thau q
         WHERE q.nam_tai_chinh = k.fy AND q.ps = k.ps AND q.ma_khach_hang = k.cust
           AND q.nhom_san_pham = k.grp AND q.loai = k.loai AND q.dot = k.dot
           AND q.so_luong > 0) THEN
      RAISE EXCEPTION 'dot_khong_co_quota: % đợt % của nhóm % chưa có quota — nhập quota cho đợt, hoặc xoá đợt nếu không dùng',
                      CASE k.loai WHEN 'chinh' THEN 'Thầu chính' ELSE 'Thầu bổ sung' END, k.dot, k.grp
        USING ERRCODE = '22023';
    END IF;
  END LOOP;

  RETURN jsonb_build_object('dot', v_n_dot, 'quota', v_n_quota);
END;
$function$;

REVOKE ALL ON FUNCTION public.luu_quota_thau(jsonb, jsonb, text, text, text, text[], text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.luu_quota_thau(jsonb, jsonb, text, text, text, text[], text) TO service_role;

COMMIT;
