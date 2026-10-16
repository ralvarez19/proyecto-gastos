class LocalProvider {
  const LocalProvider({
    required this.clientId,
    required this.name,
    required this.contact,
    required this.phone,
    required this.syncStatus,
    required this.updatedAt,
    this.remoteId,
    this.isDeleted = false,
  });

  final String clientId;
  final String? remoteId;
  final String name;
  final String contact;
  final String phone;
  final String syncStatus;
  final DateTime updatedAt;
  final bool isDeleted;

  Map<String, Object?> toMap() => {
    'client_id': clientId,
    'remote_id': remoteId,
    'name': name,
    'contact': contact,
    'phone': phone,
    'sync_status': syncStatus,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'is_deleted': isDeleted ? 1 : 0,
  };

  factory LocalProvider.fromMap(Map<String, Object?> map) => LocalProvider(
    clientId: map['client_id']! as String,
    remoteId: map['remote_id'] as String?,
    name: map['name']! as String,
    contact: (map['contact'] as String?) ?? '',
    phone: (map['phone'] as String?) ?? '',
    syncStatus: map['sync_status']! as String,
    updatedAt: DateTime.parse(map['updated_at']! as String).toLocal(),
    isDeleted: (map['is_deleted']! as int) == 1,
  );
}
