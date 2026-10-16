enum AttendanceKind { full, half, absent, rest }

class LocalWorkerRole {
  const LocalWorkerRole({
    required this.clientId,
    required this.name,
    required this.active,
    required this.syncStatus,
    required this.updatedAt,
  });
  final String clientId, name, syncStatus;
  final bool active;
  final DateTime updatedAt;
  Map<String, Object?> toMap() => {
    'client_id': clientId,
    'name': name,
    'active': active ? 1 : 0,
    'sync_status': syncStatus,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'is_deleted': 0,
  };
  factory LocalWorkerRole.fromMap(Map<String, Object?> m) => LocalWorkerRole(
    clientId: '${m['client_id']}',
    name: '${m['name']}',
    active: (m['active'] as num).toInt() == 1,
    syncStatus: '${m['sync_status']}',
    updatedAt: DateTime.parse('${m['updated_at']}').toLocal(),
  );
}

double attendanceFactor(AttendanceKind kind) => switch (kind) {
  AttendanceKind.full => 1,
  AttendanceKind.half => 0.5,
  AttendanceKind.absent || AttendanceKind.rest => 0,
};

int calculateLaborCents({
  required int dailyRateCents,
  required AttendanceKind attendance,
  double allocation = 1,
}) => (dailyRateCents * attendanceFactor(attendance) * allocation.clamp(0, 1))
    .round();

class LocalWorker {
  const LocalWorker({
    required this.clientId,
    this.remoteId,
    required this.fullName,
    required this.nationalId,
    required this.phone,
    required this.roleId,
    required this.defaultRateCents,
    required this.startDate,
    required this.status,
    required this.notes,
    required this.projectIds,
    required this.syncStatus,
    required this.updatedAt,
  });
  final String clientId;
  final String? remoteId;
  final String fullName;
  final String nationalId;
  final String phone;
  final String roleId;
  final int defaultRateCents;
  final DateTime startDate;
  final String status;
  final String notes;
  final List<String> projectIds;
  final String syncStatus;
  final DateTime updatedAt;
  Map<String, Object?> toMap() => {
    'client_id': clientId,
    'remote_id': remoteId,
    'full_name': fullName,
    'national_id': nationalId,
    'phone': phone,
    'role_id': roleId,
    'default_rate_cents': defaultRateCents,
    'start_date': _date(startDate),
    'status': status,
    'notes': notes,
    'project_ids': projectIds.join(','),
    'sync_status': syncStatus,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'is_deleted': 0,
  };
  factory LocalWorker.fromMap(Map<String, Object?> m) => LocalWorker(
    clientId: '${m['client_id']}',
    remoteId: m['remote_id'] as String?,
    fullName: '${m['full_name']}',
    nationalId: '${m['national_id'] ?? ''}',
    phone: '${m['phone'] ?? ''}',
    roleId: '${m['role_id'] ?? 'otros'}',
    defaultRateCents: (m['default_rate_cents'] as num).toInt(),
    startDate: DateTime.parse('${m['start_date']}'),
    status: '${m['status']}',
    notes: '${m['notes'] ?? ''}',
    projectIds: '${m['project_ids'] ?? ''}'
        .split(',')
        .where((e) => e.isNotEmpty)
        .toList(),
    syncStatus: '${m['sync_status']}',
    updatedAt: DateTime.parse('${m['updated_at']}').toLocal(),
  );
}

class LocalAttendance {
  const LocalAttendance({
    required this.clientId,
    required this.workerId,
    required this.projectId,
    required this.date,
    required this.kind,
    required this.appliedRateCents,
    required this.allocationBps,
    required this.earnedCents,
    required this.notes,
    required this.revision,
    required this.syncStatus,
    required this.updatedAt,
  });
  final String clientId, workerId, projectId, notes, syncStatus;
  final DateTime date, updatedAt;
  final AttendanceKind kind;
  final int appliedRateCents, allocationBps, earnedCents, revision;
  Map<String, Object?> toMap() => {
    'client_id': clientId,
    'worker_id': workerId,
    'project_id': projectId,
    'attendance_date': _date(date),
    'attendance_type': kind.name.toUpperCase(),
    'applied_rate_cents': appliedRateCents,
    'allocation_bps': allocationBps,
    'earned_cents': earnedCents,
    'notes': notes,
    'revision': revision,
    'sync_status': syncStatus,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'is_deleted': 0,
  };
  factory LocalAttendance.fromMap(Map<String, Object?> m) => LocalAttendance(
    clientId: '${m['client_id']}',
    workerId: '${m['worker_id']}',
    projectId: '${m['project_id']}',
    date: DateTime.parse('${m['attendance_date']}'),
    kind: AttendanceKind.values.firstWhere(
      (e) => e.name.toUpperCase() == '${m['attendance_type']}',
      orElse: () => AttendanceKind.absent,
    ),
    appliedRateCents: (m['applied_rate_cents'] as num).toInt(),
    allocationBps: (m['allocation_bps'] as num).toInt(),
    earnedCents: (m['earned_cents'] as num).toInt(),
    notes: '${m['notes'] ?? ''}',
    revision: (m['revision'] as num).toInt(),
    syncStatus: '${m['sync_status']}',
    updatedAt: DateTime.parse('${m['updated_at']}').toLocal(),
  );
}

class LocalAdvance {
  const LocalAdvance({
    required this.clientId,
    required this.workerId,
    required this.projectId,
    required this.date,
    required this.amountCents,
    required this.method,
    required this.reference,
    required this.notes,
    required this.appliedCents,
    required this.syncStatus,
    required this.updatedAt,
  });
  final String clientId,
      workerId,
      projectId,
      method,
      reference,
      notes,
      syncStatus;
  final DateTime date, updatedAt;
  final int amountCents, appliedCents;
  Map<String, Object?> toMap() => {
    'client_id': clientId,
    'worker_id': workerId,
    'project_id': projectId,
    'advance_date': _date(date),
    'amount_cents': amountCents,
    'method': method,
    'reference': reference,
    'notes': notes,
    'applied_cents': appliedCents,
    'sync_status': syncStatus,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'is_deleted': 0,
  };
  factory LocalAdvance.fromMap(Map<String, Object?> m) => LocalAdvance(
    clientId: '${m['client_id']}',
    workerId: '${m['worker_id']}',
    projectId: '${m['project_id'] ?? ''}',
    date: DateTime.parse('${m['advance_date']}'),
    amountCents: (m['amount_cents'] as num).toInt(),
    method: '${m['method']}',
    reference: '${m['reference'] ?? ''}',
    notes: '${m['notes'] ?? ''}',
    appliedCents: (m['applied_cents'] as num).toInt(),
    syncStatus: '${m['sync_status']}',
    updatedAt: DateTime.parse('${m['updated_at']}').toLocal(),
  );
}

class LocalWorkerPayment {
  const LocalWorkerPayment({
    required this.clientId,
    required this.workerId,
    required this.projectId,
    required this.periodStart,
    required this.periodEnd,
    required this.date,
    required this.amountCents,
    required this.method,
    required this.reference,
    required this.notes,
    required this.syncStatus,
    required this.updatedAt,
  });
  final String clientId,
      workerId,
      projectId,
      method,
      reference,
      notes,
      syncStatus;
  final DateTime periodStart, periodEnd, date, updatedAt;
  final int amountCents;
  Map<String, Object?> toMap() => {
    'client_id': clientId,
    'worker_id': workerId,
    'project_id': projectId,
    'period_start': _date(periodStart),
    'period_end': _date(periodEnd),
    'payment_date': _date(date),
    'amount_cents': amountCents,
    'method': method,
    'reference': reference,
    'notes': notes,
    'sync_status': syncStatus,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'is_deleted': 0,
  };
  factory LocalWorkerPayment.fromMap(Map<String, Object?> m) =>
      LocalWorkerPayment(
        clientId: '${m['client_id']}',
        workerId: '${m['worker_id']}',
        projectId: '${m['project_id'] ?? ''}',
        periodStart: DateTime.parse('${m['period_start']}'),
        periodEnd: DateTime.parse('${m['period_end']}'),
        date: DateTime.parse('${m['payment_date']}'),
        amountCents: (m['amount_cents'] as num).toInt(),
        method: '${m['method']}',
        reference: '${m['reference'] ?? ''}',
        notes: '${m['notes'] ?? ''}',
        syncStatus: '${m['sync_status']}',
        updatedAt: DateTime.parse('${m['updated_at']}').toLocal(),
      );
}

class LaborSummary {
  const LaborSummary({
    required this.earnedCents,
    required this.advanceCents,
    required this.paymentCents,
    required this.pendingCents,
    required this.advanceCreditCents,
  });
  final int earnedCents,
      advanceCents,
      paymentCents,
      pendingCents,
      advanceCreditCents;
}

LaborSummary summarizeLabor(
  List<LocalAttendance> attendance,
  List<LocalAdvance> advances,
  List<LocalWorkerPayment> payments,
) {
  final earned = attendance.fold(0, (s, e) => s + e.earnedCents);
  final advanceTotal = advances.fold(0, (s, e) => s + e.amountCents);
  final paid = payments.fold(0, (s, e) => s + e.amountCents);
  final applied = advanceTotal.clamp(0, earned);
  return LaborSummary(
    earnedCents: earned,
    advanceCents: applied,
    paymentCents: paid,
    pendingCents: (earned - applied - paid).clamp(0, 1 << 62),
    advanceCreditCents: (advanceTotal - earned).clamp(0, 1 << 62),
  );
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
