import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_mobile/data/local_labor.dart';

void main() {
  test('calcula jornadas completas, medias y distribuidas', () {
    expect(
      calculateLaborCents(
        dailyRateCents: 3000,
        attendance: AttendanceKind.full,
      ),
      3000,
    );
    expect(
      calculateLaborCents(
        dailyRateCents: 2500,
        attendance: AttendanceKind.half,
      ),
      1250,
    );
    expect(
      calculateLaborCents(
        dailyRateCents: 4000,
        attendance: AttendanceKind.full,
        allocation: .5,
      ),
      2000,
    );
    expect(
      calculateLaborCents(
        dailyRateCents: 3000,
        attendance: AttendanceKind.absent,
      ),
      0,
    );
  });

  test(
    'anticipos mayores al ganado quedan como crédito sin saldo negativo',
    () {
      final now = DateTime(2026, 10, 14);
      final attendance = LocalAttendance(
        clientId: 'a',
        workerId: 'w',
        projectId: 'p',
        date: now,
        kind: AttendanceKind.full,
        appliedRateCents: 3000,
        allocationBps: 10000,
        earnedCents: 3000,
        notes: '',
        revision: 1,
        syncStatus: 'pending',
        updatedAt: now,
      );
      final advance = LocalAdvance(
        clientId: 'v',
        workerId: 'w',
        projectId: 'p',
        date: now,
        amountCents: 5000,
        method: 'CASH',
        reference: '',
        notes: '',
        appliedCents: 0,
        syncStatus: 'pending',
        updatedAt: now,
      );
      final summary = summarizeLabor([attendance], [advance], []);
      expect(summary.pendingCents, 0);
      expect(summary.advanceCents, 3000);
      expect(summary.advanceCreditCents, 2000);
    },
  );
}
