import { describe, expect, it } from 'vitest';
import { calculateEarned, summarizeLabor } from './labor-calculator';
import { WorkerAdvance, WorkerAttendance, WorkerPayment } from './models';

const attendance = (overrides: Partial<WorkerAttendance>): WorkerAttendance => ({
  id: crypto.randomUUID(), workerId: 'w1', projectId: 'p1', date: '2026-10-14',
  status: 'FULL', appliedRate: 30, allocation: 1, earned: 30, notes: '', revision: 1,
  ...overrides,
});

describe('cálculo de jornales', () => {
  it('calcula jornada completa, media jornada y distribución', () => {
    expect(calculateEarned(30, 'FULL')).toBe(30);
    expect(calculateEarned(25, 'HALF')).toBe(12.5);
    expect(calculateEarned(40, 'FULL', 0.5)).toBe(20);
    expect(calculateEarned(40, 'ABSENT')).toBe(0);
  });

  it('descuenta anticipos y pagos sin producir saldo negativo', () => {
    const rows = [attendance({}), attendance({ status: 'HALF', earned: 15 })];
    const advances = [{ id: 'a1', workerId: 'w1', projectId: 'p1', date: '2026-10-14', amount: 20, method: 'CASH', reference: '', notes: '', appliedAmount: 0 }] as WorkerAdvance[];
    const payments = [{ id: 'x1', workerId: 'w1', projectId: 'p1', periodStart: '2026-10-13', periodEnd: '2026-10-19', date: '2026-10-19', amount: 10, method: 'CASH', reference: '', notes: '' }] as WorkerPayment[];
    expect(summarizeLabor(rows, advances, payments)).toMatchObject({ earned: 45, advances: 20, payments: 10, pending: 15, advanceCredit: 0 });
  });

  it('conserva como crédito el anticipo mayor al ganado', () => {
    const advances = [{ id: 'a1', workerId: 'w1', projectId: '', date: '2026-10-14', amount: 50, method: 'TRANSFER', reference: 'TRX', notes: '', appliedAmount: 0 }] as WorkerAdvance[];
    expect(summarizeLabor([attendance({ earned: 30 })], advances, [])).toMatchObject({ pending: 0, advances: 30, advanceCredit: 20 });
  });
});
