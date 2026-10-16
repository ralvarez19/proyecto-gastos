import { WorkerAdvance, WorkerAttendance, WorkerPayment } from './models';

export interface LaborSummary {
  fullDays: number;
  halfDays: number;
  equivalentDays: number;
  earned: number;
  advances: number;
  payments: number;
  pending: number;
  advanceCredit: number;
}

export function attendanceFactor(status: WorkerAttendance['status']) {
  return status === 'FULL' ? 1 : status === 'HALF' ? 0.5 : 0;
}

export function calculateEarned(rate: number, status: WorkerAttendance['status'], allocation = 1) {
  const safeAllocation = Math.max(0, Math.min(1, allocation));
  return money(rate * attendanceFactor(status) * safeAllocation);
}

export function summarizeLabor(
  attendance: WorkerAttendance[],
  advances: WorkerAdvance[],
  payments: WorkerPayment[],
): LaborSummary {
  const fullDays = attendance.filter((item) => item.status === 'FULL').length;
  const halfDays = attendance.filter((item) => item.status === 'HALF').length;
  const equivalentDays = money(
    attendance.reduce((sum, item) => sum + attendanceFactor(item.status) * item.allocation, 0),
  );
  const earned = money(attendance.reduce((sum, item) => sum + item.earned, 0));
  const advancesTotal = money(advances.reduce((sum, item) => sum + item.amount, 0));
  const paymentsTotal = money(payments.reduce((sum, item) => sum + item.amount, 0));
  const appliedAdvances = Math.min(earned, advancesTotal);
  return {
    fullDays,
    halfDays,
    equivalentDays,
    earned,
    advances: appliedAdvances,
    payments: paymentsTotal,
    pending: money(Math.max(0, earned - appliedAdvances - paymentsTotal)),
    advanceCredit: money(Math.max(0, advancesTotal - earned)),
  };
}

export function money(value: number) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}
