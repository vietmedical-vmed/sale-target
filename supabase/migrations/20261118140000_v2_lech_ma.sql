-- V2 liên kết quota ↔ hợp đồng: lệch mã sản phẩm (user chốt 18/11/2026).
-- File duyệt: bao-cao/de-xuat-V2-lech-ma-2026-11-18.xlsx.
--
-- A. Bổ sung 67 mã chung HĐ vào shared.dm_vat_tu + 2 vào shared.dm_bo_vat_tu (theo bản sửa):
--    - thiết bị Arthrex series TH.AR.A04 → "Thiết bị" (AR-TB); dụng cụ series TH.AR.A01 → "CCDC"
--      (ma_san_pham 'Chưa có' như 230 dòng CCDC sẵn có), KHÔNG ghép vào vật tư tiêu hao;
--    - VCEM_110190, 2703vis: SP mới đúng mã đang có trong quota;
--    - MC.UO.CT1.050 / .052 (Gối primary U2) → bộ "Gối thường - UOC" (UO.GTPT1), thêm dòng bộ mới;
--    - còn lại theo đích đề xuất. Bỏ 4 mã đích sai (thanh dọc ít xâm lấn, bóng nong kèm bơm, Viper).
--    Dòng mới chép thuộc tính từ dòng mẫu cùng SP; KHÔNG chép dat_hang / muc_do_sd / safety_stock
--    (không kéo theo cảnh báo tồn kho); giá chỉ chép khi cùng SP. ma_bravo = mã chung HĐ.
--    Ảnh hưởng: trigger app_sale.san_pham_theo_danh_muc gán tên SP cho hóa đơn MỚI có mã này.
-- B1. Bảng app_sale.khoa_sp_alias + app_sale.quota_theo_khoa đọc bảng này: 47 cặp quota ↔ HĐ
--    mức Cao coi là cùng SP khi đối chiếu, RIÊNG từng KH (loại Rotapro ↔ Túi vô trùng, MOP ↔ COC dài).
-- B2. 14 SP kế hoạch (cặp SL bằng nhau, giá khớp, chưa có thực hiện) đổi mã SP (và tên nếu danh
--    mục khác) sang SP theo HĐ; giá giữ nguyên. Quota đi theo qua trigger trg_sale_target_ma_sp_quota
--    / giu_khoa. BV0324 Nẹp cổ trước Artus 1 tầng (lẻ) ↔ bộ UL.AR1: không đổi kế hoạch, chỉ ghép (B1).
-- Log: app_sale.quota_chuan_hoa_log buoc 'v2_lech_ma_20261118'. Rollback:
-- supabase/rollbacks/20261118140000_v2_lech_ma_ROLLBACK.sql
BEGIN;

-- ===== A. danh mục =====
CREATE TEMP TABLE _a (ma_chung text, ten text, ma_ncc text, tpl_id bigint, ma_sp_moi text, sp_moi text, giu_gia boolean, ghi_chu text) ON COMMIT DROP;
INSERT INTO _a VALUES
  ('MC.BI.CT1.159', 'CT1_Hệ thống trộn, bơm áp lực đẩy xi măng', 'VCEM_110190', 82926, 'VCEM_110190', 'Hệ thống trộn, bơm áp lực đẩy xi măng', false, 'SP mới theo mã quota VCEM_110190'),
  ('MC.UO.CT1.051', 'CT1_Chuôi nối dài xương đùi (đã bao gồm vít chốt)', '2703vis', 83458, '2703vis', 'Chuôi nối dài xương đùi (đã bao gồm vít chốt)', false, 'SP mới theo mã quota 2703vis'),
  ('MC.UO.CT1.047', 'CT1_Chuôi nối dài PSA loại cong (2703)', '2703 cong', 83716, NULL, NULL, true, 'Áp như đề xuất: → 2703 cong'),
  ('MC.ZB.CT2.017', 'CT2_Lót mâm chày Persona loại CR (42-5210)', '42-5210-xxx-xx', 83912, NULL, NULL, true, 'Áp như đề xuất: → 42-5x10-xxx-xxx'),
  ('MC.ZB.CT2.027', 'CT2_Lót mâm chày Persona MC (gộp trái phải)', '42-5x21-xxx-xx', 83942, NULL, NULL, true, 'Áp như đề xuất: → 42-5221-xxx-xx'),
  ('MC.ZB.CT2.029', 'CT2_Mâm chày Persona (gộp trái/phải)', '42-5320-xxx-xxx', 84043, NULL, NULL, true, 'Áp như đề xuất: → 42-5320-xxx-02'),
  ('TH.AR.A02.0092', 'Vít treo TightRope cho kỹ thuật BTB', 'AR-1588BTB', 84639, NULL, NULL, true, 'Áp như đề xuất: → AR-1588RT'),
  ('TH.BS.IC07.0558', 'Bộ dụng cụ và dây phá xơ vữa lòng mạch ROTAWIRE and wireClip Torquer (Hộp 5 cái)', 'H80223xxxxxxx; H80222xxxxxxx', 82384, NULL, NULL, true, 'Áp như đề xuất: → H7493946xxxx'),
  ('TH.BS.IO01.0096', 'Bộ Coil nút mạch bằng kim loại Interlock', 'M00136xxxx', 82790, NULL, NULL, true, 'Áp như đề xuất: → M001361xxx'),
  ('TH.SN.P08.026', 'Băng dán chống thấm nước và vi khuẩn', '66000708', 83419, NULL, NULL, true, 'Áp như đề xuất: → 66000709'),
  ('TH.SN.P08.030', 'Băng dán chống thấm nước và vi khuẩn', '66000715', 83419, NULL, NULL, true, 'Áp như đề xuất: → 66000709'),
  ('TH.SN.P08.062', 'Miếng dán cố định ống thông và bảo vệ khu vực tiêm', '66004011', 83421, NULL, NULL, true, 'Áp như đề xuất: → 66004009'),
  ('TH.SN.P08.063', 'Băng dán chống thấm nước và vi khuẩn', '66000712', 83419, NULL, NULL, true, 'Áp như đề xuất: → 66000709'),
  ('TH.AR.A01.0016', 'Dụng cụ thắt nút chỉ khâu', 'AR-1305', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0019', 'Dụng cụ gắp sụn, đầu tù 3.4mm', 'AR-12500NR', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0020', 'Dụng cụ gắp chỉ thẳng, 3.4mm', 'AR-12540', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0021', 'Dụng cụ luồn chỉ 2.75, đầu cong lên 22°', 'AR-11890', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0022', 'Dụng cụ luồn chỉ 2.75, đầu cong lên 45°', 'AR-11800', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0023', 'Dụng cụ luồn chỉ, đầu cong lên 15°', 'AR-2167-2', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0026', 'Dụng cụ luồn chỉ, đầu cong lên', 'AR-1312', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0027', 'Dụng cụ mài sụn viền', 'AR-1309', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0031', 'Ống thông, chuyển cổng, cỡ 8.25 mm x 7 cm', 'AR-6531', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0032', 'Ống thông, chuyển cổng cỡ 6 mm x 7 cm', 'AR-6536', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0033', 'Ống thông, chuyển cổng, cỡ 8.25 mm x 9 cm', 'AR-6541', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0034', 'Dụng cụ luồn chỉ', 'AR-5068H', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0035', 'Dụng cụ luồn chỉ, đầu cong 45 độ trái', 'AR-5068-45L', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0036', 'Dụng cụ luồn chỉ, đầu cong 45 độ phải', 'AR-5068-45R', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0037', 'Dụng cụ luồn chỉ, đầu cong 90 độ trái', 'AR-5068-90L', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0038', 'Dụng cụ luồn chỉ, đầu cong 90 độ phải', 'AR-5068-90R', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0042', 'Mũi khoan cho vít neo Pushlock 2.9mm', 'AR-2923D', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0046', 'Dụng cụ lấy dấu cho vít neo Pushlock 3.5mm', 'AR-1926P', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0048', 'Dụng cụ lấy dấu cho vít neo Corkscrew FT 5.5mm, Swivelock 4.75 mm và 5.5mm', 'AR-1927PB', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0049', 'Dụng cụ lấy dấu cho vít neo Corkscrew FT 4.5mm và Pushlock 4.5mm', 'AR-1922P', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0056', 'Dụng cụ cắt chỉ dẹt', 'AR-13250/AR-11794L', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0108', 'Dụng cụ lấy gân chân ngỗng (hamstring)', 'AR-10300', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0113', 'Mũi khoan rỗng cỡ 7mm', 'AR-1407', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0115', 'Mũi khoan rỗng cỡ 8mm', 'AR-1408', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0117', 'Mũi khoan rỗng cỡ 9mm', 'AR-1409', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0119', 'Mũi khoan rỗng cỡ 10mm', 'AR-1410', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0136', 'Dụng cụ đo kích thước gân', 'AR-1886', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0137', 'Dụng cụ bắt vít Biocomposite', 'AR-1996CD-1', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0146', 'Hộp dụng cụ tái tạo dây chằng chéo trước', 'AR-1900C', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0179', 'Hộp đựng dụng cụ làm gân', 'AR-2950DC', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0201', 'Dụng cụ cắt sụn 3.4mm, cong phải 30 độ', 'AR-12042', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0203', 'Dụng cụ cắt sụn 3.4mm, cong trái 30 độ', 'AR-12043', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0319', 'Kìm gặm mô loại đầu cong phải 30 độ, 3.4mm', 'AR-12020', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0320', 'Kìm gặm mô loại đầu cong trái 30 độ, 3.4mm', 'AR-12030', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0341', 'Dụng cụ dẫn hướng trocar', 'AR-6549', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0342', 'Dụng cụ dẫn hướng trocar AR-6563', 'AR-6563', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0343', 'Dụng cụ đặt trocar mềm', 'AR-6592', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A01.0348', 'Dụng cụ móc chỉ', 'AR-5007H', 84189, NULL, NULL, false, 'CCDC Arthrex (dụng cụ series TH.AR.A01)'),
  ('TH.AR.A04.0002', 'Đầu Camera 4K', 'AR-3210-0031', 84503, NULL, NULL, true, 'Thiết bị (AR-TB) – như đề xuất: → AR-TB'),
  ('TH.AR.A04.0003', 'Dây dẫn sáng đường kính 5.0 mm, dài 274 cm', 'AR-3240-5027', 84504, NULL, NULL, true, 'Thiết bị (AR-TB) – như đề xuất: → AR-TB'),
  ('TH.AR.A04.0004', 'Màn hình nội soi 32" UHD 4K', 'AR-3250-3211', 84505, NULL, NULL, true, 'Thiết bị (AR-TB) – như đề xuất: → AR-TB'),
  ('TH.AR.A04.0005', 'Kệ để hệ thống máy cho loại màn hình 32''''', 'AR-5995-16STI', 84506, NULL, NULL, true, 'Thiết bị (AR-TB) – như đề xuất: → AR-TB'),
  ('TH.AR.A04.0007', 'Ống soi 4K, 30°, đường kính 4 mm, dài 152.5 mm', 'AR-3350-4031', 84508, NULL, NULL, true, 'Thiết bị (AR-TB) – như đề xuất: → AR-TB'),
  ('TH.AR.A04.0008', 'Nòng ống soi 4mm, 2 cổng xả', 'AR-3373-4002', 84509, NULL, NULL, true, 'Thiết bị (AR-TB) – như đề xuất: → AR-TB'),
  ('TH.AR.A04.0009', 'Que dẫn hướng có cán', 'AR-3375-4001', 84510, NULL, NULL, true, 'Thiết bị (AR-TB) – như đề xuất: → AR-TB'),
  ('TH.AR.A04.0012', 'Máy bào khớp', 'AR-8305', 84513, NULL, NULL, true, 'Thiết bị (AR-TB) – như đề xuất: → AR-TB'),
  ('TH.AR.A04.0014', 'Máy cắt đốt bằng sóng radio (Dao RF)', 'AR-9800', 84514, NULL, NULL, true, 'Thiết bị (AR-TB) – như đề xuất: → AR-TB'),
  ('TH.AR.A04.0015', 'Máy bơm một chiều', 'AR-6485', 84515, NULL, NULL, true, 'Thiết bị (AR-TB) – như đề xuất: → AR-TB'),
  ('TH.AR.A04.0016', 'Tay điều khiển lưỡi bào', 'AR-8332H', 84516, NULL, NULL, true, 'Thiết bị (AR-TB) – như đề xuất: → AR-TB'),
  ('TH.AR.A04.0024', 'Bộ xử lý hình ảnh Synergy ID', 'AR-3200-0025', 84520, NULL, NULL, true, 'Thiết bị (AR-TB) – như đề xuất: → AR-TB'),
  ('TH.AR.A04.0039', 'Ống soi, 30°, đường kính 2.4 mm, dài 72 mm', 'AR-3350-2430', 84523, NULL, NULL, true, 'Thiết bị (AR-TB) – như đề xuất: → AR-TB'),
  ('TH.AR.A04.0040', 'Trocar dùng cho ống soi đường kính 2.4mm, 2 van khóa', 'AR-3372-2402', 84524, NULL, NULL, true, 'Thiết bị (AR-TB) – như đề xuất: → AR-TB'),
  ('TH.AR.A04.0041', 'Que dẫn hướng có cán dùng cho ống soi 2.4mm', 'AR-3375-2401', 84525, NULL, NULL, true, 'Thiết bị (AR-TB) – như đề xuất: → AR-TB'),
  ('TH.AR.A04.0060', 'Bộ xử lý hình ảnh Synergy Vision', 'AR-3200-0027', 84527, NULL, NULL, true, 'Thiết bị (AR-TB) – như đề xuất: → AR-TB');
CREATE TEMP TABLE _abo (ma_chung text, tpl_id bigint, ghi_chu text) ON COMMIT DROP;
INSERT INTO _abo VALUES
  ('MC.UO.CT1.050', 2335, 'UO.GTPT1.1 CT1_Gối primary U2 loại E-XUC vitamin E có miếng ghép bù xương mâm chày'),
  ('MC.UO.CT1.052', 2335, 'UO.GTPT1.2 CT1_Gối primary U2 loại E-XUC vitamin E (không gồm bánh chè)');

DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM _a a WHERE EXISTS (SELECT 1 FROM shared.dm_vat_tu v WHERE trim(v.ma_chung) = a.ma_chung)
     OR EXISTS (SELECT 1 FROM shared.dm_bo_vat_tu b WHERE trim(b.ma_chung) = a.ma_chung);
  IF v_n > 0 THEN RAISE EXCEPTION 'v2: % mã chung đã có trong danh mục', v_n; END IF;
  SELECT count(*) INTO v_n FROM _abo a WHERE EXISTS (SELECT 1 FROM shared.dm_bo_vat_tu b WHERE trim(b.ma_chung) = a.ma_chung)
     OR EXISTS (SELECT 1 FROM shared.dm_vat_tu v WHERE trim(v.ma_chung) = a.ma_chung);
  IF v_n > 0 THEN RAISE EXCEPTION 'v2: % mã chung bộ đã có trong danh mục', v_n; END IF;
  SELECT count(*) INTO v_n FROM _a a LEFT JOIN shared.dm_vat_tu t ON t.id = a.tpl_id WHERE t.id IS NULL;
  IF v_n > 0 THEN RAISE EXCEPTION 'v2: % dòng mẫu dm_vat_tu không còn', v_n; END IF;
END $$;

WITH moi AS (
  INSERT INTO shared.dm_vat_tu
    (ma_bravo, ten_vat_tu, ma_ncc, bu, nhom_san_pham, san_pham, phan_loai_1, phan_loai_2, hang, ma_hang,
     don_gia_thau_cu, don_gia_thau_moi, phan_loai, ma_chung, ma_san_pham, don_gia_mua, bu_code)
  SELECT a.ma_chung, a.ten, a.ma_ncc, t.bu, t.nhom_san_pham, coalesce(a.sp_moi, t.san_pham), t.phan_loai_1, t.phan_loai_2,
         t.hang, t.ma_hang,
         CASE WHEN a.giu_gia THEN t.don_gia_thau_cu END, CASE WHEN a.giu_gia THEN t.don_gia_thau_moi END,
         t.phan_loai, a.ma_chung, coalesce(a.ma_sp_moi, t.ma_san_pham), CASE WHEN a.giu_gia THEN t.don_gia_mua END, t.bu_code
  FROM _a a JOIN shared.dm_vat_tu t ON t.id = a.tpl_id
  RETURNING *
)
INSERT INTO app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'v2_lech_ma_20261118', 'dm_vat_tu', m.id, NULL, to_jsonb(m) FROM moi m;

WITH moi AS (
  INSERT INTO shared.dm_bo_vat_tu (nhom_san_pham, bo_vat_tu, updated_at, bu, ma_chung, ma_bo_vat_tu, bu_code)
  SELECT t.nhom_san_pham, t.bo_vat_tu, now(), t.bu, a.ma_chung, t.ma_bo_vat_tu, t.bu_code
  FROM _abo a JOIN shared.dm_bo_vat_tu t ON t.id = a.tpl_id
  RETURNING *
)
INSERT INTO app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'v2_lech_ma_20261118', 'dm_bo_vat_tu', m.id, NULL, to_jsonb(m) FROM moi m;

-- ===== B1. ghép mã theo KH =====
CREATE TABLE app_sale.khoa_sp_alias (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ma_kh text,                 -- NULL = mọi KH
  nut_tu text NOT NULL,       -- nút phía quota: 'S:'/'B:' mã SP, 'Q:' tên SP khi quota không có mã
  nut_den text NOT NULL,      -- nút phía HĐ (thường 'C:' mã chung)
  ghi_chu text,
  nguon text,
  tao_luc timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (ma_kh, nut_tu)
);
ALTER TABLE app_sale.khoa_sp_alias ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON app_sale.khoa_sp_alias FROM public, anon, authenticated;
COMMENT ON TABLE app_sale.khoa_sp_alias IS
  'Ghép mã SP quota ↔ HĐ đã duyệt, chỉ dùng cho đối chiếu / liên kết quota ↔ hợp đồng (app_sale.quota_theo_khoa). Không sửa danh mục, quota hay kế hoạch.';

INSERT INTO app_sale.khoa_sp_alias (ma_kh, nut_tu, nut_den, ghi_chu, nguon) VALUES
  ('BV0025', 'S:AR-7206', 'C:MC.AR.CT2.015', 'Trong năm: AR-7206 Chỉ tròn kèm kim ↔ AR-7200 CT2_Chỉ FiberWire #2 (Mỹ)', '{B}'),
  ('BV0025', 'S:CS 3882', 'C:MC.UL.CT1.054', 'Trong năm: CS 3882 Vít đa trục thường ↔ UL.UCT1 CT1_Vít đa trục mũ vít bước ren vuông uCentum kèm vít khóa', '{B}'),
  ('BV0026', 'S:AR-7206', 'C:MC.AR.CT2.015', 'Trong năm: AR-7206 Chỉ tròn kèm kim ↔ AR-7200 CT2_Chỉ FiberWire #2 (Mỹ)', '{B}'),
  ('BV0040', 'S:C2A12', 'C:TH.AP.A09.0006', 'Trong năm: C2A12 Cổng nội soi 1 lỗ âm đạo ↔ C2A11 Cổng phẫu thuật nội soi qua đường âm đạo GelPOINT Vpath, 11cm (C2A11)', '{B}'),
  ('BV0040', 'S:CFF73', 'C:TH.AP.A07.0004', 'Trong năm: CFF73 Bộ Trocar (1 vỏ - 1 nòng) các loại ↔ CFF03 Trocar, 5X100MM Kii FIOS ADV FIX SYS 6/BX (CFF03)', '{B}'),
  ('BV0042', 'S:66800041', 'C:TH.SN.P08.003', 'Trong năm: 66800041 Cắt lọc thủy lực ↔ 66800040 Tay dao dùng 1 lần', '{B}'),
  ('BV0065', 'S:H74939352020', 'C:TH.BS.IC03.0070', 'Trong năm: H74939352020 OptiCross 40 ↔ H749518140 Ống thông chụp ảnh mạch vành OptiCross 40MHz Coronary Imaging Catheter', '{B}'),
  ('BV0065', 'S:AR-1588RT', 'C:MC.AR.CT2.031', 'Quota 1.4: AR-1588RT Vít treo TightRope luồn chỉ ↔ AR-1588RT-J Vít treo cố định dây chằng TightRope RT, có 2 lỗ luồn chỉ', '{B}'),
  ('BV0069', 'S:CTF03', 'C:TH.AP.A07.0004', 'Quota 1.4: CTF03 Bộ Trocar (1 vỏ - 1 nòng) các loại ↔ CFF03 Trocar, 5X100MM Kii FIOS ADV FIX SYS 6/BX (CFF03)', '{B}'),
  ('BV0104', 'S:AR-7206', 'C:MC.AR.CT2.015', 'Quota 1.4: AR-7206 Chỉ tròn kèm kim ↔ AR-7200 CT2_Chỉ FiberWire #2 (Mỹ)', '{B}'),
  ('BV0145', 'S:AR-4580-24', 'C:MC.AR.CT2.055', 'Quota 1.4: AR-4580-24 Dụng cụ FiberStitch ↔ AR-4570 Dụng cụ khâu sụn chêm FiberStitch cong, kèm chỉ siêu bền cỡ 0-2', '{B}'),
  ('BV0150', 'S:CS 3882', 'C:MC.UL.CT1.054', 'Quota 1.4: CS 3882 Vít đa trục thường ↔ UL.UCT1 CT1_Vít đa trục mũ vít bước ren vuông uCentum kèm vít khóa', '{B}'),
  ('BV0150', 'S:CS 3803', 'C:MC.UL.CT1.055', 'Quota 1.4: CS 3803 Vít đơn trục qua da ↔ UL.UCT2 CT1_Vít đơn trục mũ vít bước ren vuông uCentum kèm vít khóa', '{B}'),
  ('BV0189', 'S:AR-1934BCFT', 'C:MC.AR.CT2.024', 'Quota 1.4: AR-1934BCFT Vít neo Suturetak ↔ AR-1934BCF-2 CT2_BioComposite SutureTak 3.0 x 14.5mm', '{B}'),
  ('BV0294', 'S:M0013941xxxxx', 'C:TH.BS.IO05.0106', 'Trong năm: M0013941xxxxx Transend ↔ M001468010 Dây dẫn hướng dùng trong can thiệp mạch TRANSEND/.014/190CM', '{B}'),
  ('BV0295', 'S:C2A12', 'C:TH.AP.A09.0006', 'Trong năm: C2A12 Cổng nội soi 1 lỗ âm đạo ↔ C2A11 Cổng phẫu thuật nội soi qua đường âm đạo GelPOINT Vpath, 11cm (C2A11)', '{B}'),
  ('BV0298', 'S:AR-2324PCT', 'C:MC.AR.CT2.036', 'Trong năm: AR-2324PCT Vít neo Swivelock PEEK ↔ AR-2324PSLC CT2_Vít neo kèm chỉ', '{B}'),
  ('BV0304', 'S:AR-7206', 'C:MC.AR.CT2.015', 'Quota 1.4: AR-7206 Chỉ tròn kèm kim ↔ AR-7200 CT2_Chỉ FiberWire #2 (Mỹ/Anh)', '{B}'),
  ('BV0306', 'S:AR-1934BCFT', 'C:MC.AR.CT2.024', 'Trong năm: AR-1934BCFT Vít neo Suturetak ↔ AR-1934BCF-2 CT2_BioComposite SutureTak 3.0 x 14.5mm', '{B}'),
  ('BV0308', 'S:C2A12', 'C:TH.AP.A09.0006', 'Quota 1.4: C2A12 Cổng nội soi 1 lỗ âm đạo ↔ C2A11 Cổng phẫu thuật nội soi qua đường âm đạo GelPOINT Vpath, 11cm (C2A11)', '{B}'),
  ('BV0308', 'S:AR-2324PSLC', 'C:MC.AR.CT2.035', 'Quota 1.4: AR-2324PSLC Vít neo Swivelock PEEK ↔ AR-2324PCT Vít neo Swivelock kèm chỉ dẹt siêu bền, PEEK, 4.75mm x 19.1mm', '{B}'),
  ('BV0314', 'S:CTF33', 'C:TH.AP.A07.0030', 'Quota 1.4: CTF33 Bộ Trocar (1 vỏ - 1 nòng) các loại ↔ CTF03 Trocar, Kii 5x100 FIOS Z-THR 6/BX (CTF03)', '{B}'),
  ('BV0319', 'S:CTF03', 'C:TH.AP.A07.0004', 'Quota 1.4: CTF03 Bộ Trocar (1 vỏ - 1 nòng) các loại ↔ CFF03 Trocar, 5X100MM Kii FIOS ADV FIX SYS 6/BX (CFF03)', '{B}'),
  ('BV0324', 'S:SCDA39', 'C:TB.CO.P04.0212', 'Quota 1.4: SCDA39 Tay dao siêu âm ↔ SCD7A13 Tay dao siêu âm không dây SCD7A13', '{B}'),
  ('BV0324', 'S:CS 3807-300-400', 'C:MC.UL.CT1.120', 'Quota 1.4: CS 3807-300-400 Thanh dọc thường 300-400mm ↔ CS 3807-500mm CT1_Thanh dọc ucentum, loại 500mm (CS 3807)', '{B}'),
  ('BV0330', 'S:AR-1588RT', 'C:MC.AR.CT2.031', 'Quota 1.4: AR-1588RT Vít treo TightRope luồn chỉ ↔ AR-1588RT-J CT2_Vít treo (Mỹ/Anh)', '{B}'),
  ('BV0330', 'S:AR-7206', 'C:MC.AR.CT2.015', 'Quota 1.4: AR-7206 Chỉ tròn kèm kim ↔ AR-7200 CT2_Chỉ FiberWire #2 (Mỹ)', '{B}'),
  ('BV0332', 'S:C2A12', 'C:TH.AP.A09.0008', 'Trong năm: C2A12 Cổng nội soi 1 lỗ âm đạo ↔ C2A15 Cổng phẫu thuật nội soi qua đường âm đạo GelPOINT Vpath, 7cm (C2A15)', '{B}'),
  ('BV0336', 'S:AR-7206', 'C:MC.AR.CT2.015', 'Quota 1.4: AR-7206 Chỉ tròn kèm kim ↔ AR-7200 CT2_Chỉ FiberWire #2 (Mỹ)', '{B}'),
  ('BV0336', 'S:CTF03', 'C:TH.AP.A07.0037', 'Quota 1.4: CTF03 Bộ Trocar (1 vỏ - 1 nòng) các loại ↔ CTF73 Trocar, Kii 12x100 FIOS Z-THR 6/BX (CTF73)', '{B}'),
  ('BV0342', 'S:SCD7A39', 'C:TB.CO.P04.0212', 'Quota 1.4: SCD7A39 Tay dao siêu âm ↔ SCD7A13 Tay dao siêu âm không dây SCD7A13', '{B}'),
  ('BV0342', 'S:CS 3910-240 (mm)', 'C:MC.UL.CT1.094', 'Trong năm: CS 3910-240 (mm) Nẹp dọc Neon3 240mm ↔ CS 3910-20-100 CT1_Thanh dọc Neon3, loại 20-100mm (CS 3910)', '{B}'),
  ('BV0378', 'S:AR-7206', 'C:MC.AR.CT2.015', 'Quota 1.4: AR-7206 Chỉ tròn kèm kim ↔ AR-7200 CT2_Chỉ FiberWire #2 (Mỹ)', '{B}'),
  ('BV0449', 'S:AR-7206', 'C:MC.AR.CT2.015', 'Trong năm: AR-7206 Chỉ tròn kèm kim ↔ AR-7200 CT2_Chỉ FiberWire #2 (Mỹ)', '{B}'),
  ('BV0453', 'S:M0013941xxxxx', 'C:TH.BS.IO05.0108', 'Trong năm: M0013941xxxxx Transend ↔ M001468xxx Dây dẫn hướng dùng trong can thiệp mạch TRANSEND', '{B}'),
  ('BV0454', 'S:M0013941xxxxx', 'C:TH.BS.IO05.0108', 'Trong năm: M0013941xxxxx Transend ↔ M001468xxx Dây dẫn hướng dùng trong can thiệp mạch TRANSEND', '{B}'),
  ('BV0458', 'S:AR-7206', 'C:MC.AR.CT2.015', 'Trong năm: AR-7206 Chỉ tròn kèm kim ↔ AR-7200 Chỉ siêu bền Fiberwire, có kim tròn (Mỹ/Anh)', '{B}'),
  ('BV0523', 'S:AR-7206', 'C:MC.AR.CT2.015', 'Quota 1.4: AR-7206 Chỉ tròn kèm kim ↔ AR-7200 CT2_Chỉ FiberWire #2 (Mỹ)', '{B}'),
  ('BV0625', 'S:AR-7206', 'C:MC.AR.CT2.015', 'Trong năm: AR-7206 Chỉ tròn kèm kim ↔ AR-7200 Chỉ siêu bền Fiberwire, có kim tròn (Mỹ/Anh)', '{B}'),
  ('BV0628', 'S:AR-7206', 'C:MC.AR.CT2.015', 'Trong năm: AR-7206 Chỉ tròn kèm kim ↔ AR-7200 CT2_Chỉ FiberWire #2 (Mỹ)', '{B}'),
  ('BV0655', 'S:AR-7206', 'C:MC.AR.CT2.015', 'Trong năm: AR-7206 Chỉ tròn kèm kim ↔ AR-7200 CT2_Chỉ FiberWire #2 (Mỹ)', '{B}'),
  ('BV1138', 'S:SCDA26', 'C:TB.CO.P04.0211', 'Quota 1.4: SCDA26 Tay dao siêu âm ↔ SCD7A39 Tay dao siêu âm không dây SCD7A39', '{B}'),
  ('BV1355', 'S:CTF73', 'C:TH.AP.A07.0004', 'Quota 1.4: CTF73 Bộ Trocar (1 vỏ - 1 nòng) các loại ↔ CFF03 Trocar, 5X100MM Kii FIOS ADV FIX SYS 6/BX (CFF03)', '{B}'),
  ('BV1355', 'S:C8302', 'C:TH.AP.A08.0010', 'Quota 1.4: C8302 Dụng cụ nong và bảo vệ vết mổ cỡ trung bình ↔ C8402 Dụng cụ nong và bảo vệ vết mổ, ALEXIS O WND RETRACT 5-9CM 5/BX (C8402)', '{B}'),
  ('BV1478', 'S:AR-7206', 'C:MC.AR.CT2.015', 'Trong năm: AR-7206 Chỉ tròn kèm kim ↔ AR-7200 CT2_Chỉ FiberWire #2 (Mỹ)', '{B}'),
  ('BV1679', 'S:CS 3882', 'C:MC.UL.CT1.054', 'Quota 1.4: CS 3882 Vít đa trục thường ↔ UL.UCT1 CT1_Vít đa trục mũ vít bước ren vuông uCentum kèm vít khóa', '{B}'),
  ('BV0324', 'S:CS 9102-01', 'C:MC.UL.CT1.063', 'Quota 1.4: CS 9102-01 Nẹp cổ trước Artus 1 tầng ↔ UL.AR1 (lẻ ↔ bộ)', '{B}');

create or replace function app_sale.quota_theo_khoa(
  p_nam text default 'FY26',
  p_fy_start date default date '2026-04-01',
  p_thang text default null
)
returns table (
  quota_id bigint, ma_khach_hang text, khoa_sp text,
  ps text, loai text, dot integer, thang_thau text, tt text, chinh_truoc_fy boolean,
  bu text, mien text, nhom_san_pham text, san_pham text, ma_san_pham text,
  so_luong numeric, don_gia numeric,
  bung boolean, dinh_muc numeric, n_khoa_bo integer,
  sl numeric, tien numeric
)
language sql
stable
set search_path = shared, app_sale, pg_temp
as $$
with tham_so as (
  select
    coalesce(p_thang,
             (select value #>> '{}' from shared.app_config where key = 'current_month'),
             to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM')) as thang,
    to_char(p_fy_start, 'YYYY-MM') as fy_thang
),
k as (select nut, khoa from app_sale.v_khoa_so_sanh_sp),
-- ghép mã đã duyệt (app_sale.khoa_sp_alias): nút quota → nút HĐ, riêng KH hoặc mọi KH (ma_kh null)
alias as (
  select a.ma_kh, a.nut_tu, coalesce(k.khoa, a.nut_den) as khoa
  from app_sale.khoa_sp_alias a left join k on k.nut = a.nut_den
),
-- quota chính thức của năm, kèm trạng thái đợt giống lib/quota.js trangThaiDot
q0 as (
  select q.id, q.ma_khach_hang, q.ps, q.loai, q.dot, q.bu, q.mien, q.nhom_san_pham,
    q.san_pham, q.ma_san_pham, q.so_luong, q.don_gia, d.thang_thau,
    case
      when q.loai = 'cu' then 'cu'
      when shared.het_han_dot(d.thang_thau, d.thoi_gian) is null or d.thang_thau > ts.thang then 'up'
      when shared.het_han_dot(d.thang_thau, d.thoi_gian) < ts.thang
       and shared.het_han_dot(d.thang_thau, d.thoi_gian) < ts.fy_thang then 'het'
      else 'on'
    end as tt,
    (q.loai = 'chinh' and d.thang_thau < ts.fy_thang) as chinh_truoc_fy
  from shared.quota_thau q
  cross join tham_so ts
  left join shared.dot_thau d
    on d.nam_tai_chinh = q.nam_tai_chinh and d.ps = q.ps and d.ma_khach_hang = q.ma_khach_hang
   and d.nhom_san_pham = q.nhom_san_pham and d.loai = q.loai and d.dot = q.dot
  where q.nam_tai_chinh = p_nam
    and q.trang_thai = 'chinh_thuc'
    and q.bu is distinct from 'test'
    and coalesce(q.so_luong, 0) <> 0
),
-- bộ chưa có mã chung → linh kiện (nhóm thay thế đã gộp 1 khoá trong v_khoa_so_sanh_sp)
bo_bung as (
  select trim(b.ma_bo_vat_tu) as ma_bo
  from shared.dm_bo_vat_tu b
  where coalesce(trim(b.ma_chung), '') in ('', 'Chưa có')
),
gia_sp as (
  select trim(ma_san_pham) as sp, avg(nullif(don_gia_thau_moi, 0)) as gia
  from shared.dm_vat_tu
  group by 1
),
linh_kien as (
  select trim(m.ma_bo_vat_tu) as ma_bo, k.khoa,
         max(m.so_luong_dinh_muc) as dinh_muc,
         avg(g.gia) as gia
  from shared.dm_bo_vat_tu_mapping m
  join bo_bung bb on bb.ma_bo = trim(m.ma_bo_vat_tu)
  join k on k.nut = 'S:' || trim(m.ma_san_pham)
  left join gia_sp g on g.sp = trim(m.ma_san_pham)
  group by 1, 2
),
linh_kien_gia as (
  select lk.*,
    lk.dinh_muc * coalesce(lk.gia, avg(lk.gia) over (partition by lk.ma_bo), 1) as trong_so
  from linh_kien lk
),
linh_kien_w as (
  select lk.*,
    lk.trong_so / nullif(sum(lk.trong_so) over (partition by lk.ma_bo), 0) as ty_trong,
    count(*) over (partition by lk.ma_bo)::int as n_khoa
  from linh_kien_gia lk
)
-- sản phẩm lẻ / bộ có mã chung
select q0.id, q0.ma_khach_hang,
       coalesce(al.khoa, kb.khoa, ks.khoa, 'Q:' || coalesce(trim(q0.ma_san_pham), q0.san_pham)),
       q0.ps, q0.loai, q0.dot, q0.thang_thau, q0.tt, q0.chinh_truoc_fy,
       q0.bu, q0.mien, q0.nhom_san_pham, q0.san_pham, q0.ma_san_pham,
       q0.so_luong, q0.don_gia,
       false, 1::numeric, 1,
       q0.so_luong, q0.so_luong * q0.don_gia
from q0
left join k kb on kb.nut = 'B:' || trim(q0.ma_san_pham)
left join k ks on ks.nut = 'S:' || trim(q0.ma_san_pham)
left join lateral (
  select al.khoa from alias al
  where (al.ma_kh = q0.ma_khach_hang or al.ma_kh is null)
    and al.nut_tu in ('S:' || trim(q0.ma_san_pham), 'B:' || trim(q0.ma_san_pham),
                      'Q:' || coalesce(trim(q0.ma_san_pham), q0.san_pham))
  order by al.ma_kh nulls last limit 1
) al on true
where not exists (select 1 from bo_bung bb where bb.ma_bo = trim(q0.ma_san_pham))
union all
-- bộ chưa có mã chung: bung ra linh kiện (SL × định mức; tiền chia theo giá × định mức)
select q0.id, q0.ma_khach_hang, lk.khoa,
       q0.ps, q0.loai, q0.dot, q0.thang_thau, q0.tt, q0.chinh_truoc_fy,
       q0.bu, q0.mien, q0.nhom_san_pham, q0.san_pham, q0.ma_san_pham,
       q0.so_luong, q0.don_gia,
       true, lk.dinh_muc, lk.n_khoa,
       q0.so_luong * lk.dinh_muc, q0.so_luong * q0.don_gia * lk.ty_trong
from q0
join linh_kien_w lk on lk.ma_bo = trim(q0.ma_san_pham);
$$;

revoke all on function app_sale.quota_theo_khoa(text, date, text) from public, anon, authenticated;

-- ===== B2. đổi mã SP trên kế hoạch =====
CREATE TEMP TABLE _st (ps text, kh text, nhom text, bvt text, sp text, gia numeric, ma_cu text, n_mong int, ma_moi text, sp_moi text) ON COMMIT DROP;
INSERT INTO _st VALUES
  ('Lợi Phan', 'BV0038', 'NSTQ - Applied', 'Vật tư riêng lẻ - Applied', 'Bộ Trocar (1 vỏ - 1 nòng) các loại', 1504762, 'CFR33', 12, 'CFF03', 'Bộ Trocar (1 vỏ - 1 nòng) các loại'),
  ('Lợi Phan', 'BV0052', 'NSTQ - Applied', 'Vật tư riêng lẻ - Applied', 'Bộ Trocar (1 vỏ - 1 nòng) các loại', 1504762, 'CTF73', 12, 'CFF03', 'Bộ Trocar (1 vỏ - 1 nòng) các loại'),
  ('Lợi Phan', 'BV0052', 'NSTQ - Applied', 'Vật tư riêng lẻ - Applied', 'Cổng nội soi 1 lỗ hậu môn', 15599048, 'CNB11', 12, 'CNB10', 'Cổng nội soi 1 lỗ hậu môn'),
  ('Lợi Phan', 'BV0072', 'NSTQ - Applied', 'Vật tư riêng lẻ - Applied', 'Cổng nội soi 1 lỗ âm đạo', 15027619, 'C2A12', 12, 'C2A11', 'Cổng nội soi 1 lỗ âm đạo'),
  ('Tùng Phạm', 'BV0237', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ dẹt xanh', 4200000, 'AR-7500', 12, 'AR-7237', 'Chỉ dẹt xanh'),
  ('Tấn Phạm', 'BV0304', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ dẹt xanh', 4200000, 'AR-7500', 12, 'AR-7237', 'Chỉ dẹt xanh'),
  ('Hương Đồng', 'BV0320', 'BSC - IO', 'Vật tư riêng lẻ - IO', 'Transend', 2800000, 'M0013941xxxxx', 7, 'M001468xxx', 'Transend'),
  ('Nga Trần', 'BV0323', 'NSTQ - Applied', 'Vật tư riêng lẻ - Applied', 'Cổng nội soi 1 lỗ thành bụng, thành ngực', 11428571, 'CNGL2', 12, 'CNGL3', 'Cổng nội soi 1 lỗ thành bụng, thành ngực'),
  ('Tùng Phạm', 'BV0330', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ dẹt xanh', 4200000, 'AR-7500', 12, 'AR-7237', 'Chỉ dẹt xanh'),
  ('Dung Trần', 'BV0378', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Dụng cụ định vị khâu sụn chêm', 12100000, 'Chưa có', 12, 'AR-7900', 'Dụng cụ định vị khâu sụn chêm'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ tròn kèm kim', 1200000, 'AR-7206', 12, 'AR-7200', 'Chỉ tròn kèm kim'),
  ('Tứ Nguyễn', 'BV0488', 'NSK Arthrex', 'Vật tư riêng lẻ - NSK Arthrex', 'Chỉ dẹt xanh', 4200000, 'AR-7500', 12, 'AR-7237', 'Chỉ dẹt xanh'),
  ('Trang Trần', 'BV0500', 'TH DSA - Medtronic', 'Vật tư riêng lẻ - TH DSA', 'Bộ phát năng lượng (SCGAA)', 52904762, 'SCGAA', 12, 'SCG7AA', 'Bộ phát năng lượng (SCG7AA)'),
  ('Đinh Kiên', 'BV1829', 'NSTQ - Applied', 'Vật tư riêng lẻ - Applied', 'Trocar đầu tù các cỡ', 1704762, 'C0R47', 12, 'C0Q20', 'Trocar đầu tù các cỡ');

CREATE TEMP TABLE _st_cu ON COMMIT DROP AS
SELECT s.* FROM shared.sale_target s JOIN _st x
  ON s.nam_tai_chinh = 'FY26' AND s.ps = x.ps AND s.ma_khach_hang = x.kh AND s.nhom_san_pham = x.nhom
 AND s.bo_vat_tu = x.bvt AND s.san_pham = x.sp AND s.don_gia = x.gia
 AND s.ma_san_pham IS NOT DISTINCT FROM x.ma_cu AND NOT coalesce(s.ngoai_ke_hoach, false);

DO $$
DECLARE r record; v_n int;
BEGIN
  FOR r IN SELECT x.*, (SELECT count(*) FROM _st_cu c WHERE c.ps = x.ps AND c.ma_khach_hang = x.kh AND c.nhom_san_pham = x.nhom
                         AND c.bo_vat_tu = x.bvt AND c.san_pham = x.sp AND c.don_gia = x.gia) AS n_thay,
                       (SELECT coalesce(sum(c.sl_thuc_hien), 0) FROM _st_cu c WHERE c.ps = x.ps AND c.ma_khach_hang = x.kh
                         AND c.nhom_san_pham = x.nhom AND c.bo_vat_tu = x.bvt AND c.san_pham = x.sp AND c.don_gia = x.gia) AS th
           FROM _st x LOOP
    IF r.n_thay <> r.n_mong THEN RAISE EXCEPTION 'v2: % % % mong % dòng kế hoạch, thấy %', r.kh, r.sp, r.ma_cu, r.n_mong, r.n_thay; END IF;
    IF r.th <> 0 THEN RAISE EXCEPTION 'v2: % % đã có thực hiện %, không đổi', r.kh, r.sp, r.th; END IF;
  END LOOP;
END $$;

-- chụp quota của các SP kế hoạch sắp đổi (trigger sẽ đổi mã / khoá theo) để rollback trả đúng
INSERT INTO app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'v2_lech_ma_20261118', 'quota_thau', q.id, to_jsonb(q), NULL
FROM shared.quota_thau q JOIN _st x
  ON q.nam_tai_chinh = 'FY26' AND q.ps = x.ps AND q.ma_khach_hang = x.kh AND q.nhom_san_pham = x.nhom
 AND q.bo_vat_tu = x.bvt AND q.san_pham = x.sp AND q.don_gia = x.gia;

SET CONSTRAINTS shared.uq_sale_target_khoa DEFERRED;

WITH upd AS (
  UPDATE shared.sale_target s
  SET ma_san_pham = x.ma_moi, san_pham = x.sp_moi, updated_at = now()
  FROM _st x, _st_cu c
  WHERE c.id = s.id AND c.ps = x.ps AND c.ma_khach_hang = x.kh AND c.nhom_san_pham = x.nhom
    AND c.bo_vat_tu = x.bvt AND c.san_pham = x.sp AND c.don_gia = x.gia
  RETURNING s.*
)
INSERT INTO app_sale.quota_chuan_hoa_log (buoc, bang, ban_ghi_id, truoc, sau)
SELECT 'v2_lech_ma_20261118', 'sale_target', u.id, to_jsonb(c), to_jsonb(u) FROM upd u JOIN _st_cu c ON c.id = u.id;

SELECT shared.gop_dong_trung_sale_target((SELECT array_agg(id) FROM _st_cu));
SET CONSTRAINTS shared.uq_sale_target_khoa IMMEDIATE;

COMMIT;
