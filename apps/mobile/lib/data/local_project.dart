class LocalProject {
  const LocalProject({
    required this.clientId,
    required this.name,
    required this.location,
    required this.budgetCents,
    required this.spentCents,
    required this.progress,
    required this.status,
    required this.syncStatus,
    required this.updatedAt,
    this.remoteId,
    this.isDeleted = false,
  });

  final String clientId;
  final String? remoteId;
  final String name;
  final String location;
  final int budgetCents;
  final int spentCents;
  final double progress;
  final String status;
  final String syncStatus;
  final DateTime updatedAt;
  final bool isDeleted;

  int get availableCents => budgetCents - spentCents;
  double get budgetUsed => budgetCents == 0 ? 0 : spentCents / budgetCents;
  String get formattedBudget => '\$${(budgetCents / 100).toStringAsFixed(2)}';
  String get formattedSpent => '\$${(spentCents / 100).toStringAsFixed(2)}';

  Map<String, Object?> toMap() => {
    'client_id': clientId,
    'remote_id': remoteId,
    'name': name,
    'location': location,
    'budget_cents': budgetCents,
    'spent_cents': spentCents,
    'progress': progress,
    'status': status,
    'sync_status': syncStatus,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'is_deleted': isDeleted ? 1 : 0,
  };

  factory LocalProject.fromMap(Map<String, Object?> map) => LocalProject(
    clientId: map['client_id']! as String,
    remoteId: map['remote_id'] as String?,
    name: map['name']! as String,
    location: map['location']! as String,
    budgetCents: map['budget_cents']! as int,
    spentCents: map['spent_cents']! as int,
    progress: (map['progress']! as num).toDouble(),
    status: (map['status'] as String?) ?? 'ACTIVE',
    syncStatus: map['sync_status']! as String,
    updatedAt: DateTime.parse(map['updated_at']! as String).toLocal(),
    isDeleted: (map['is_deleted']! as int) == 1,
  );
}
