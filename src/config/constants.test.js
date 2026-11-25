import { describe, it, expect, afterEach } from 'vitest';
import { CURRENT_MONTH, setCurrentMonth, duKienThang } from './constants.js';

const goc = CURRENT_MONTH;
afterEach(() => setCurrentMonth(goc));

describe('duKienThang', () => {
  it('past month uses actual, future month uses KH update', () => {
    setCurrentMonth('2026-11');
    expect(duKienThang('2026-10', 3, 10)).toBe(3);
    expect(duKienThang('2026-12', 3, 10)).toBe(10);
  });

  it('current month uses KH update when actual is still below it', () => {
    setCurrentMonth('2026-11');
    expect(duKienThang('2026-11', 3, 10)).toBe(10);
    expect(duKienThang('2026-11', 0, 10)).toBe(10);
  });

  it('current month keeps actual when it already beats KH update (incl. out-of-plan rows)', () => {
    setCurrentMonth('2026-11');
    expect(duKienThang('2026-11', 12, 10)).toBe(12);
    expect(duKienThang('2026-11', 5, 0)).toBe(5);
  });
});
