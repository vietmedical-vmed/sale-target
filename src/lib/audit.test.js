import { describe, it, expect } from 'vitest';
import { chenhLech, fmtGiaTri, fmtThang, khoangNgay, tieuDeNgay, tomTatNhom, actionColor } from './audit.js';

describe('audit helpers', () => {
  it('fmtGiaTri phân biệt trống và 0', () => {
    expect(fmtGiaTri('sl_ke_hoach_update', null)).toBe('trống');
    expect(fmtGiaTri('sl_ke_hoach_update', 0)).toBe('0');
    expect(fmtGiaTri('san_pham', 'Bipolar')).toBe('Bipolar');
    expect(fmtGiaTri('sl_ke_hoach_update', 1234.5)).toBe('1,234.5');
  });

  it('chenhLech coi trống là 0, bỏ qua cột chữ', () => {
    expect(chenhLech('sl_ke_hoach_update', null, 3)).toBe(3);
    expect(chenhLech('sl_ke_hoach_update', 5, 2)).toBe(-3);
    expect(chenhLech('san_pham', 'a', 'b')).toBeNull();
  });

  it('fmtThang', () => {
    expect(fmtThang('2027-03')).toBe('T3/27');
    expect(fmtThang('')).toBe('');
  });

  it('khoangNgay', () => {
    const now = new Date(2026, 10, 7, 15, 0);
    expect(khoangNgay('all', '', '', now)).toEqual({ from: null, to: null });
    expect(khoangNgay('today', '', '', now).from).toBe(new Date(2026, 10, 7).toISOString());
    expect(khoangNgay('7d', '', '', now).from).toBe(new Date(2026, 10, 1).toISOString());
    expect(khoangNgay('month', '', '', now).from).toBe(new Date(2026, 10, 1).toISOString());
    const c = khoangNgay('custom', '2026-11-01', '2026-11-05', now);
    expect(c.to).toBe(new Date(2026, 10, 6).toISOString());
  });

  it('tieuDeNgay đánh dấu hôm nay / hôm qua', () => {
    const now = new Date(2026, 10, 7, 9);
    expect(tieuDeNgay('2026-11-07', now)).toBe('Hôm nay · Thứ bảy, 07/11/2026');
    expect(tieuDeNgay('2026-11-06', now)).toBe('Hôm qua · Thứ sáu, 06/11/2026');
    expect(tieuDeNgay('2026-11-03', now)).toBe('Thứ ba, 03/11/2026');
  });

  it('tomTatNhom', () => {
    expect(
      tomTatNhom({ action: 'updateCells', cot: ['revUpd'], tong_dong: 12, khach_hang: ['BV A', 'BV B'], so_kh: 5 }),
    ).toBe('SL KH update · 12 dòng · BV A, BV B +3 KH');
    expect(tomTatNhom({ action: 'saveDotThau', tong_dong: 1, khach_hang: null, ps: ['Thanh Ngô'], so_ps: 1 })).toBe(
      '1 dòng · PS Thanh Ngô',
    );
  });

  it('actionColor: thao tác xoá màu đỏ', () => {
    expect(actionColor('deleteProduct')).toContain('red');
    expect(actionColor('updateCells')).toContain('blue');
  });
});

describe('gộp tháng', () => {
  it('gộp cùng KH/SP/cột/giá trị, tách khi giá trị khác', async () => {
    const { gopThang, fmtKhoangThang } = await import('./audit.js');
    const base = { kh: 'BV A', sp: 'X', bo: 'X', cot: 'don_gia', cu: 1, moi: 2 };
    const rows = [
      { ...base, thang: '2026-05' },
      { ...base, cot: 'sl_ke_hoach_update', cu: 0, moi: 3, thang: '2026-05' },
      { ...base, thang: '2026-04' },
      { ...base, thang: '2026-06' },
    ];
    const g = gopThang(rows);
    expect(g).toHaveLength(2);
    expect(g[0].thangs).toEqual(['2026-04', '2026-05', '2026-06']);
    expect(fmtKhoangThang(g[0].thangs)).toBe('T4/26 – T6/26');
    expect(fmtKhoangThang(['2026-04', '2026-06'])).toBe('T4/26, T6/26');
    expect(fmtKhoangThang(['2026-12', '2027-01'])).toBe('T12/26 – T1/27');
  });
});
