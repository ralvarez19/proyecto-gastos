import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_mobile/data/local_expense.dart';
import 'package:gastos_mobile/data/local_project.dart';
import 'package:gastos_mobile/services/export_service.dart';

void main() {
  final date = DateTime.utc(2026, 8, 16, 12);
  final projects = [
    LocalProject(
      clientId: 'project-test',
      name: 'Casa Prueba',
      location: 'Guayaquil',
      budgetCents: 6000000,
      spentCents: 82000,
      progress: .1,
      status: 'ACTIVE',
      syncStatus: 'pending',
      updatedAt: date,
    ),
    LocalProject(
      clientId: 'project-test-2',
      name: 'Casa Samborondon',
      location: 'La Puntilla',
      budgetCents: 7200000,
      spentCents: 50000,
      progress: .08,
      status: 'ACTIVE',
      syncStatus: 'demo',
      updatedAt: date,
    ),
    LocalProject(
      clientId: 'project-test-3',
      name: 'Casa Olon',
      location: 'Santa Elena',
      budgetCents: 4800000,
      spentCents: 8000,
      progress: .04,
      status: 'PAUSED',
      syncStatus: 'demo',
      updatedAt: date,
    ),
  ];
  final expenses = [
    LocalExpense(
      clientId: 'expense-test',
      projectName: 'Casa Prueba',
      category: 'Materiales · Cemento',
      description: '100 sacos de cemento',
      provider: 'Proveedor prueba',
      invoiceNumber: '001-020-000380000',
      quantity: 100,
      unitPriceCents: 820,
      subtotalCents: 82000,
      taxRateBps: 1500,
      taxCents: 12300,
      totalCents: 94300,
      expenseDate: date,
      createdAt: date,
      updatedAt: date,
      syncStatus: 'pending',
    ),
    LocalExpense(
      clientId: 'expense-test-2',
      projectName: 'Casa Samborondon',
      category: 'Mano de obra · Albanil',
      description: 'Pago de cuadrilla',
      provider: 'Juan C.',
      quantity: 1,
      unitPriceCents: 50000,
      subtotalCents: 50000,
      taxRateBps: 1500,
      taxCents: 7500,
      totalCents: 57500,
      expenseDate: date,
      createdAt: date,
      updatedAt: date,
      syncStatus: 'demo',
    ),
    LocalExpense(
      clientId: 'expense-test-3',
      projectName: 'Casa Olon',
      category: 'Otros · Transporte',
      description: 'Transporte de arena',
      provider: 'Transcarga',
      quantity: 1,
      unitPriceCents: 8000,
      subtotalCents: 8000,
      taxRateBps: 0,
      taxCents: 0,
      totalCents: 8000,
      expenseDate: date,
      createdAt: date,
      updatedAt: date,
      syncStatus: 'demo',
    ),
  ];

  test('genera un PDF válido con contenido', () async {
    final bytes = await ExportService.buildPdfBytes(
      expenses: expenses,
      projects: projects,
    );

    expect(bytes.length, greaterThan(1000));
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
    if (const bool.fromEnvironment('WRITE_EXPORT_PREVIEW')) {
      final directory = Directory('tmp/pdfs');
      await directory.create(recursive: true);
      await File(
        '${directory.path}/obraflow-report-preview.pdf',
      ).writeAsBytes(bytes, flush: true);
    }
  });

  test('genera un Excel con las hojas esperadas', () {
    final bytes = ExportService.buildExcelBytes(
      expenses: expenses,
      projects: projects,
    );
    final workbook = Excel.decodeBytes(bytes);

    expect(
      workbook.tables.keys,
      containsAll(['Resumen', 'Resumen por proyecto', 'Gastos', 'Proyectos']),
    );
    expect(workbook['Gastos'].maxRows, 4);
    expect(workbook['Resumen por proyecto'].maxRows, 4);
    expect(
      workbook['Gastos']
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1))
          .value,
      TextCellValue('001-020-000380000'),
    );
  });
}
