export const MONTHS = [
  '2026-04', '2026-05', '2026-06', '2026-07', '2026-08', '2026-09',
  '2026-10', '2026-11', '2026-12', '2027-01', '2027-02', '2027-03',
];

export const MONTH_LABELS = [
  'T4', 'T5', 'T6', 'T7', 'T8', 'T9', 'T10', 'T11', 'T12', 'T1', 'T2', 'T3',
];

export let CURRENT_MONTH = '2026-09';
export function setCurrentMonth(m) { CURRENT_MONTH = m; }

export const getCurIdx = () => MONTHS.indexOf(CURRENT_MONTH);
export const getNoteMonth = () => MONTHS[Math.max(0, getCurIdx() - 1)];
export const isYtdMonth = (mo) => (mo || '') <= CURRENT_MONTH;

export const NO_MSET = '(Không phân loại)';
export const TOK_KEY = 'sp_tok';

export const ROLE_LABELS = {
  admin: 'Quản trị',
  manager: 'Quản lý',
  area_manager: 'Quản lý miền',
  product_manager: 'Quản lý ngành hàng',
  ps: 'Sale (PS)',
};

export const TEAMS = {
  chcs: { label: 'CH&CS', name: 'CHCS', gradient: '#2a78d6' },
  cttm: { label: 'CTTM & CTUT', name: 'CTTM', gradient: '#1baf7a' },
  thnk: { label: 'THNS & CSVT', name: 'THNK', gradient: '#eda100' },
  test: { label: 'TEST', name: 'TEST', gradient: '#898781' },
};

export const TEAM_ALL = {
  label: 'Tất cả',
  name: 'Tất cả team',
  gradient: 'linear-gradient(135deg,#2a78d6,#1baf7a,#eda100)',
};

export const canSwitchTeam = (role) => role === 'admin' || role === 'manager';

export const OOP_CUST = 'Ngoài kế hoạch';

export const LY_DO_LABEL = {
  chua_co_dia_ban: { short: 'Chưa có địa bàn', color: 'red', desc: 'KH × nhóm SP chưa được khai báo địa bàn' },
  thieu_dong_ke_hoach: { short: 'Thiếu SP trong KH', color: 'amber', desc: 'Địa bàn đúng PS, kế hoạch chưa có sản phẩm này' },
  sai_bo_vat_tu: { short: 'Sai bộ vật tư', color: 'orange', desc: 'Kế hoạch có SP nhưng khác bộ vật tư' },
  sai_ps: { short: 'Sai PS', color: 'red', desc: 'Hoá đơn ghi PS khác PS trong địa bàn' },
  ps_la: { short: 'PS ngoài dm_ps', color: 'red', desc: 'PS trong hoá đơn không có trong danh mục PS' },
};

export let MASK_MONEY = false;
export function setMaskMoney(v) { MASK_MONEY = v; }

export let ALIAS_MAP = new Map();
export function setAliasMap(m) { ALIAS_MAP = m; }
