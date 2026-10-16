class LocalExpense {
  const LocalExpense({
    required this.clientId,
    required this.projectName,
    required this.category,
    required this.description,
    required this.provider,
    this.invoiceNumber = '',
    required this.quantity,
    required this.unitPriceCents,
    required this.subtotalCents,
    required this.taxRateBps,
    required this.taxCents,
    required this.totalCents,
    required this.expenseDate,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
    this.remoteId,
    this.isDeleted = false,
  });

  final String clientId;
  final String? remoteId;
  final String projectName;
  final String category;
  final String description;
  final String provider;
  final String invoiceNumber;
  final double quantity;
  final int unitPriceCents;
  final int subtotalCents;
  final int taxRateBps;
  final int taxCents;
  final int totalCents;
  final DateTime expenseDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus;
  final bool isDeleted;

  String get formattedTotal => '\$${(totalCents / 100).toStringAsFixed(2)}';
  String get formattedSubtotal =>
      '\$${(subtotalCents / 100).toStringAsFixed(2)}';
  String get formattedTax => '\$${(taxCents / 100).toStringAsFixed(2)}';
  double get taxRatePercent => taxRateBps / 100;

  Map<String, Object?> toMap() => {
    'client_id': clientId,
    'remote_id': remoteId,
    'project_name': projectName,
    'category': category,
    'description': description,
    'provider': provider,
    'invoice_number': invoiceNumber,
    'quantity': quantity,
    'unit_price_cents': unitPriceCents,
    'subtotal_cents': subtotalCents,
    'tax_rate_bps': taxRateBps,
    'tax_cents': taxCents,
    'total_cents': totalCents,
    'expense_date': expenseDate.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'sync_status': syncStatus,
    'is_deleted': isDeleted ? 1 : 0,
  };

  factory LocalExpense.fromMap(Map<String, Object?> map) => LocalExpense(
    clientId: map['client_id']! as String,
    remoteId: map['remote_id'] as String?,
    projectName: map['project_name']! as String,
    category: map['category']! as String,
    description: map['description']! as String,
    provider: map['provider']! as String,
    invoiceNumber: (map['invoice_number'] as String?) ?? '',
    quantity: (map['quantity']! as num).toDouble(),
    unitPriceCents: map['unit_price_cents']! as int,
    subtotalCents:
        (map['subtotal_cents'] as int?) ?? map['total_cents']! as int,
    taxRateBps: (map['tax_rate_bps'] as int?) ?? 0,
    taxCents: (map['tax_cents'] as int?) ?? 0,
    totalCents: map['total_cents']! as int,
    expenseDate: DateTime.parse(map['expense_date']! as String).toLocal(),
    createdAt: DateTime.parse(map['created_at']! as String).toLocal(),
    updatedAt: DateTime.parse(map['updated_at']! as String).toLocal(),
    syncStatus: map['sync_status']! as String,
    isDeleted: (map['is_deleted']! as int) == 1,
  );
}
