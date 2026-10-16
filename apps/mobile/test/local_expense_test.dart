import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_mobile/data/local_expense.dart';

void main() {
  test('conserva centavos y metadatos de sincronización al mapear', () {
    final now = DateTime.utc(2026, 8, 15, 12);
    final expense = LocalExpense(
      clientId: 'expense-local-1',
      projectName: 'Casa Ceibos',
      category: 'Materiales · Cemento',
      description: 'Cemento Holcim',
      provider: 'Disensa',
      quantity: 100,
      unitPriceCents: 820,
      subtotalCents: 82000,
      taxRateBps: 1500,
      taxCents: 12300,
      totalCents: 94300,
      expenseDate: now,
      createdAt: now,
      updatedAt: now,
      syncStatus: 'pending',
    );

    final restored = LocalExpense.fromMap(expense.toMap());

    expect(restored.totalCents, 94300);
    expect(restored.formattedTotal, '\$943.00');
    expect(restored.formattedTax, '\$123.00');
    expect(restored.syncStatus, 'pending');
    expect(restored.clientId, 'expense-local-1');
  });
}
