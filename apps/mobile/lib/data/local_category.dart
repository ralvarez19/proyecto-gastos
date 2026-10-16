class LocalCategory {
  const LocalCategory({
    required this.clientId,
    required this.name,
    required this.groupName,
    required this.syncStatus,
    required this.updatedAt,
    this.remoteId,
    this.isDeleted = false,
  });

  final String clientId;
  final String? remoteId;
  final String name;
  final String groupName;
  final String syncStatus;
  final DateTime updatedAt;
  final bool isDeleted;

  String get fullName => '$groupName · $name';

  Map<String, Object?> toMap() => {
    'client_id': clientId,
    'remote_id': remoteId,
    'name': name,
    'group_name': groupName,
    'sync_status': syncStatus,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'is_deleted': isDeleted ? 1 : 0,
  };

  factory LocalCategory.fromMap(Map<String, Object?> map) => LocalCategory(
    clientId: map['client_id']! as String,
    remoteId: map['remote_id'] as String?,
    name: map['name']! as String,
    groupName: map['group_name']! as String,
    syncStatus: map['sync_status']! as String,
    updatedAt: DateTime.parse(map['updated_at']! as String).toLocal(),
    isDeleted: (map['is_deleted']! as int) == 1,
  );
}
