-- Hoàn tác 20261029110000_dot_moi_kem_quota: upsert_dot_thau lại cho tạo đợt rỗng, bỏ luu_quota_thau.
-- Phải deploy lại edge function bản trước (saveQuotaThau gọi upsert_quota_thau) TRƯỚC khi chạy file này.

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
$function$
;

DROP FUNCTION IF EXISTS public.luu_quota_thau(jsonb, jsonb, text, text, text, text[], text);

COMMIT;
