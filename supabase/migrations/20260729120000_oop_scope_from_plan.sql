-- Ngoài kế hoạch: suy ra BU / Miền / Nhóm SP từ dữ liệu kế hoạch
--
-- VẤN ĐỀ
-- sv_bovattu_actual.bu ghi "CH&CS" trong khi sale_target.bu ghi "chcs" (hai
-- nguồn nhập khác nhau). Edge function sale_target-api lọc quyền bằng
-- applyScope():
--     admin/manager chọn 1 team  -> .eq("bu", payload.bu)   -- payload.bu = "chcs"
--     role khác                  -> .eq("bu", sess.b)       -- sess.b   = "chcs"
-- "CH&CS" <> "chcs" nên không dòng nào khớp → phần ngoài kế hoạch CHỈ hiện khi
-- admin chọn "All BU" (lúc đó không có filter bu). PS / area_manager / manager
-- không bao giờ thấy phần ngoài kế hoạch của chính mình.
-- (Kiểm chứng 2026-07-29: 804 dòng OOP, tất cả bu = "CH&CS".)
--
-- CÁCH SỬA
-- View tự suy ra bu / nhom_san_pham (và chuẩn hoá tên PS, miền) từ sale_target:
--   - PS  -> BU, Miền, cách viết PS chuẩn  (ps_ref)
--   - Sản phẩm -> Nhóm SP                  (sp_ref)
-- Lấy giá trị phổ biến nhất trong kế hoạch để tránh lệch chính tả/hoa thường.
-- Nhờ vậy quyền xem của dòng ngoài kế hoạch bám đúng theo PS: PS đó xem được,
-- và các cấp trên (area_manager theo miền, manager/admin theo BU) cũng xem được.
--
-- Cột của view giữ nguyên tên/thứ tự → edge function không phải đổi gì.

DROP VIEW IF EXISTS v_actual_ngoai_ke_hoach;

CREATE VIEW v_actual_ngoai_ke_hoach AS
WITH ps_ref AS (
  -- PS (chuẩn hoá) -> cách viết chuẩn + BU + Miền, theo tổ hợp xuất hiện nhiều nhất
  SELECT ps_n, ps_canon, bu, mien
  FROM (
    SELECT lower(btrim(s.ps)) AS ps_n,
           s.ps               AS ps_canon,
           s.bu               AS bu,
           s.mien             AS mien,
           row_number() OVER (PARTITION BY lower(btrim(s.ps))
                              -- ưu tiên tổ hợp có BU/Miền thật, rồi mới tới tổ hợp nhiều dòng nhất
                              ORDER BY (coalesce(btrim(s.bu),   '') <> '') DESC,
                                       (coalesce(btrim(s.mien), '') <> '') DESC,
                                       count(*) DESC) AS rn
    FROM   sale_target s
    WHERE  coalesce(btrim(s.ps), '') <> ''
    GROUP  BY 1, 2, 3, 4
  ) t
  WHERE rn = 1
),
bu_ref AS (
  -- BU rút gọn (bỏ ký tự đặc biệt, thường hoá) -> cách viết chuẩn trong sale_target.
  -- Dự phòng cho dòng có PS chưa xuất hiện trong kế hoạch: 'CH&CS' -> 'chcs'.
  SELECT bu_n, bu_canon
  FROM (
    SELECT regexp_replace(lower(btrim(s.bu)), '[^a-z0-9]', '', 'g') AS bu_n,
           s.bu                                                     AS bu_canon,
           row_number() OVER (PARTITION BY regexp_replace(lower(btrim(s.bu)), '[^a-z0-9]', '', 'g')
                              ORDER BY count(*) DESC)               AS rn
    FROM   sale_target s
    WHERE  coalesce(btrim(s.bu), '') <> ''
    GROUP  BY 1, 2
  ) t
  WHERE rn = 1
),
sp_ref AS (
  -- Sản phẩm (chuẩn hoá) -> Nhóm SP, theo nhóm xuất hiện nhiều nhất
  SELECT sp_n, nhom_san_pham
  FROM (
    SELECT lower(btrim(s.san_pham)) AS sp_n,
           s.nhom_san_pham,
           row_number() OVER (PARTITION BY lower(btrim(s.san_pham))
                              ORDER BY count(*) DESC) AS rn
    FROM   sale_target s
    WHERE  coalesce(btrim(s.san_pham), '')      <> ''
      AND  coalesce(btrim(s.nhom_san_pham), '') <> ''
    GROUP  BY 1, 2
  ) t
  WHERE rn = 1
)
SELECT a.thang_ke_hoach,
       -- miền lấy từ actual, thiếu thì suy từ PS
       coalesce(nullif(btrim(a.mien), ''), p.mien)                     AS mien,
       -- PS viết theo đúng chính tả trong kế hoạch để .eq("ps", ...) khớp
       coalesce(p.ps_canon, a.ps)                                      AS ps,
       a.ma_khach_hang,
       a.khach_hang,
       -- ưu tiên BU suy từ PS (cùng vốn từ với sale_target), rồi tới BU của actual
       -- đã quy về cách viết chuẩn, cuối cùng mới giữ nguyên giá trị thô
       coalesce(p.bu, b.bu_canon, nullif(btrim(a.bu), ''))             AS bu,
       coalesce(g.nhom_san_pham, nullif(btrim(a.nhom_san_pham), ''))   AS nhom_san_pham,
       a.bo_vat_tu,
       a.san_pham,
       a.sl_thuc_hien
FROM   sv_bovattu_actual a
LEFT   JOIN ps_ref p ON p.ps_n  = lower(btrim(a.ps))
LEFT   JOIN bu_ref b ON b.bu_n  = regexp_replace(lower(btrim(a.bu)), '[^a-z0-9]', '', 'g')
LEFT   JOIN sp_ref g ON g.sp_n  = lower(btrim(a.san_pham))
WHERE  NOT EXISTS (
         SELECT 1
         FROM   sale_target s
         WHERE  s.thang_ke_hoach = a.thang_ke_hoach
           AND  lower(btrim(coalesce(s.ps,            ''))) = lower(btrim(coalesce(a.ps,            '')))
           AND  lower(btrim(coalesce(s.ma_khach_hang, ''))) = lower(btrim(coalesce(a.ma_khach_hang, '')))
           AND  lower(btrim(coalesce(s.bo_vat_tu,     ''))) = lower(btrim(coalesce(a.bo_vat_tu,     '')))
           AND  lower(btrim(coalesce(s.san_pham,      ''))) = lower(btrim(coalesce(a.san_pham,      '')))
       );

COMMENT ON VIEW v_actual_ngoai_ke_hoach IS
  'Actual không khớp dòng kế hoạch nào. BU/Miền/Nhóm SP suy từ sale_target theo PS và sản phẩm để phân quyền xem đúng theo PS và các cấp trên.';

-- config.toml để auto_expose_new_tables TẮT -> view mới KHÔNG tự lộ qua Data API,
-- kể cả cho service_role (edge function sale_target-api dùng service_role).
GRANT SELECT ON v_actual_ngoai_ke_hoach TO service_role, anon, authenticated;
