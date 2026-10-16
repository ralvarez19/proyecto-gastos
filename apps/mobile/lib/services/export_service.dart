import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../data/local_expense.dart';
import '../data/local_project.dart';

class ExportService {
  const ExportService._();

  static Future<File> createExcel({
    required List<LocalExpense> expenses,
    required List<LocalProject> projects,
    String? periodLabel,
  }) => _writeFile(
    'Reporte_ObraFlow_${_fileDate()}.xlsx',
    buildExcelBytes(
      expenses: expenses,
      projects: projects,
      periodLabel: periodLabel,
    ),
  );

  static Uint8List buildExcelBytes({
    required List<LocalExpense> expenses,
    required List<LocalProject> projects,
    String? periodLabel,
  }) {
    final workbook = Excel.createExcel();
    workbook.rename('Sheet1', 'Resumen');
    final summary = workbook['Resumen'];
    summary.appendRow([TextCellValue('OBRAFLOW - REPORTE DE GASTOS')]);
    summary.appendRow([
      TextCellValue('Generado'),
      TextCellValue(_dateTime(DateTime.now())),
    ]);
    if (periodLabel != null) {
      summary.appendRow([TextCellValue('Período'), TextCellValue(periodLabel)]);
    }
    summary.appendRow([
      TextCellValue('Proyectos'),
      IntCellValue(projects.length),
    ]);
    summary.appendRow([
      TextCellValue('Gastos registrados'),
      IntCellValue(expenses.length),
    ]);
    summary.appendRow([
      TextCellValue('Total USD'),
      DoubleCellValue(_total(expenses) / 100),
    ]);
    _styleHeader(summary, 0, 1);
    summary.setColumnWidth(0, 24);
    summary.setColumnWidth(1, 22);

    final projectSummary = workbook['Resumen por proyecto'];
    projectSummary.appendRow([
      TextCellValue('Proyecto'),
      TextCellValue('Presupuesto'),
      TextCellValue('Gastado'),
      TextCellValue('Disponible'),
      TextCellValue('Movimientos'),
      TextCellValue('IVA'),
      TextCellValue('Materiales'),
      TextCellValue('Mano de obra'),
      TextCellValue('Otros'),
    ]);
    for (final project in projects) {
      final projectExpenses = _expensesForProject(expenses, project.name);
      projectSummary.appendRow([
        TextCellValue(project.name),
        DoubleCellValue(project.budgetCents / 100),
        DoubleCellValue(project.spentCents / 100),
        DoubleCellValue(project.availableCents / 100),
        IntCellValue(projectExpenses.length),
        DoubleCellValue(_taxTotal(projectExpenses) / 100),
        DoubleCellValue(_categoryTotal(projectExpenses, 'Materiales') / 100),
        DoubleCellValue(_categoryTotal(projectExpenses, 'Mano de obra') / 100),
        DoubleCellValue(_categoryTotal(projectExpenses, 'Otros') / 100),
      ]);
    }
    _styleHeader(projectSummary, 0, 9);
    for (var column = 0; column < 9; column++) {
      projectSummary.setColumnWidth(column, column == 0 ? 24 : 17);
    }
    final summaryMoneyStyle = CellStyle(
      numberFormat: CustomNumericNumFormat(formatCode: '\$#,##0.00'),
    );
    for (var row = 1; row <= projects.length; row++) {
      for (final column in [1, 2, 3, 5, 6, 7, 8]) {
        projectSummary
                .cell(
                  CellIndex.indexByColumnRow(
                    columnIndex: column,
                    rowIndex: row,
                  ),
                )
                .cellStyle =
            summaryMoneyStyle;
      }
    }

    final expenseSheet = workbook['Gastos'];
    expenseSheet.appendRow([
      TextCellValue('Fecha'),
      TextCellValue('Factura'),
      TextCellValue('Proyecto'),
      TextCellValue('Categoria'),
      TextCellValue('Descripcion'),
      TextCellValue('Proveedor'),
      TextCellValue('Cantidad'),
      TextCellValue('Precio unitario'),
      TextCellValue('Subtotal'),
      TextCellValue('IVA %'),
      TextCellValue('IVA'),
      TextCellValue('Total'),
      TextCellValue('Sincronizacion'),
    ]);
    for (final expense in expenses) {
      expenseSheet.appendRow([
        TextCellValue(_date(expense.expenseDate)),
        TextCellValue(expense.invoiceNumber),
        TextCellValue(expense.projectName),
        TextCellValue(expense.category),
        TextCellValue(expense.description),
        TextCellValue(expense.provider),
        DoubleCellValue(expense.quantity),
        DoubleCellValue(expense.unitPriceCents / 100),
        DoubleCellValue(expense.subtotalCents / 100),
        DoubleCellValue(expense.taxRatePercent / 100),
        DoubleCellValue(expense.taxCents / 100),
        DoubleCellValue(expense.totalCents / 100),
        TextCellValue(expense.syncStatus),
      ]);
    }
    _styleHeader(expenseSheet, 0, 13);
    for (var column = 0; column < 13; column++) {
      expenseSheet.setColumnWidth(column, column == 4 ? 28 : 18);
    }
    final moneyStyle = CellStyle(
      numberFormat: CustomNumericNumFormat(formatCode: '\$#,##0.00'),
    );
    for (var row = 1; row <= expenses.length; row++) {
      expenseSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row))
              .cellStyle =
          moneyStyle;
      for (final column in [8, 10, 11]) {
        expenseSheet
                .cell(
                  CellIndex.indexByColumnRow(
                    columnIndex: column,
                    rowIndex: row,
                  ),
                )
                .cellStyle =
            moneyStyle;
      }
    }

    final projectSheet = workbook['Proyectos'];
    projectSheet.appendRow([
      TextCellValue('Proyecto'),
      TextCellValue('Ubicacion'),
      TextCellValue('Presupuesto'),
      TextCellValue('Gastado'),
      TextCellValue('Disponible'),
      TextCellValue('Avance'),
      TextCellValue('Estado'),
    ]);
    for (final project in projects) {
      projectSheet.appendRow([
        TextCellValue(project.name),
        TextCellValue(project.location),
        DoubleCellValue(project.budgetCents / 100),
        DoubleCellValue(project.spentCents / 100),
        DoubleCellValue(project.availableCents / 100),
        DoubleCellValue(project.progress),
        TextCellValue(project.status),
      ]);
    }
    _styleHeader(projectSheet, 0, 7);
    for (var column = 0; column < 7; column++) {
      projectSheet.setColumnWidth(column, 20);
    }

    final bytes = workbook.save();
    if (bytes == null) throw StateError('No se pudo generar el archivo Excel.');
    return Uint8List.fromList(bytes);
  }

  static Future<File> createPdf({
    required List<LocalExpense> expenses,
    required List<LocalProject> projects,
    String? periodLabel,
  }) async => _writeFile(
    'Reporte_ObraFlow_${_fileDate()}.pdf',
    await buildPdfBytes(
      expenses: expenses,
      projects: projects,
      periodLabel: periodLabel,
    ),
  );

  static Future<Uint8List> buildPdfBytes({
    required List<LocalExpense> expenses,
    required List<LocalProject> projects,
    String? periodLabel,
  }) async {
    final document = pw.Document(
      title: 'Reporte de gastos ObraFlow',
      author: 'ObraFlow',
      subject: 'Control local de gastos de construccion',
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.green700, width: 1.5),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'OBRAFLOW',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.green800,
                ),
              ),
              pw.Text(
                'Reporte de gastos',
                style: const pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Pagina ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          pw.SizedBox(height: 16),
          pw.Text(
            'Resumen financiero',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Generado el ${_dateTime(DateTime.now())}',
            style: const pw.TextStyle(color: PdfColors.grey700),
          ),
          if (periodLabel != null)
            pw.Text(
              'Período: $periodLabel',
              style: const pw.TextStyle(color: PdfColors.grey700),
            ),
          pw.SizedBox(height: 18),
          pw.Row(
            children: [
              _pdfMetric('Proyectos', '${projects.length}'),
              pw.SizedBox(width: 10),
              _pdfMetric('Movimientos', '${expenses.length}'),
              pw.SizedBox(width: 10),
              _pdfMetric(
                'Total registrado',
                '\$${(_total(expenses) / 100).toStringAsFixed(2)}',
              ),
              pw.SizedBox(width: 10),
              _pdfMetric(
                'IVA incluido',
                '\$${(_taxTotal(expenses) / 100).toStringAsFixed(2)}',
              ),
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            'Resumen por proyecto',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          for (final project in projects)
            _pdfProjectSummary(
              project,
              _expensesForProject(expenses, project.name),
            ),
          pw.NewPage(),
          pw.Text(
            'Detalle de gastos',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Fecha',
              'Factura',
              'Proyecto',
              'Descripcion',
              'Categoria',
              'Subtotal',
              'IVA',
              'Total',
            ],
            data: expenses
                .map(
                  (expense) => [
                    _date(expense.expenseDate),
                    _pdfSafe(expense.invoiceNumber),
                    _pdfSafe(expense.projectName),
                    _pdfSafe(expense.description),
                    _pdfSafe(expense.category),
                    expense.formattedSubtotal,
                    '${expense.taxRatePercent.toStringAsFixed(0)}% ${expense.formattedTax}',
                    expense.formattedTotal,
                  ],
                )
                .toList(),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green700),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.all(5),
            columnWidths: {
              0: const pw.FlexColumnWidth(.8),
              1: const pw.FlexColumnWidth(1.1),
              2: const pw.FlexColumnWidth(1.1),
              3: const pw.FlexColumnWidth(1.5),
              4: const pw.FlexColumnWidth(1.2),
              5: const pw.FlexColumnWidth(.7),
              6: const pw.FlexColumnWidth(.7),
              7: const pw.FlexColumnWidth(.7),
            },
          ),
        ],
      ),
    );
    return document.save();
  }

  static Future<void> shareFile(File file, {required String title}) async {
    await SharePlus.instance.share(
      ShareParams(
        title: title,
        subject: title,
        text: 'Reporte generado desde ObraFlow',
        files: [XFile(file.path)],
      ),
    );
  }

  static Future<File> _writeFile(String name, Uint8List bytes) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static pw.Widget _pdfMetric(String label, String value) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    ),
  );

  static pw.Widget _pdfProjectSummary(
    LocalProject project,
    List<LocalExpense> expenses,
  ) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 12),
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          _pdfSafe(project.name),
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        if (project.location.isNotEmpty)
          pw.Text(
            _pdfSafe(project.location),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            _pdfMetric('Presupuesto', project.formattedBudget),
            pw.SizedBox(width: 6),
            _pdfMetric('Gastado', project.formattedSpent),
            pw.SizedBox(width: 6),
            _pdfMetric(
              'Disponible',
              '\$${(project.availableCents / 100).toStringAsFixed(2)}',
            ),
            pw.SizedBox(width: 6),
            _pdfMetric('Movimientos', '${expenses.length}'),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Materiales: \$${(_categoryTotal(expenses, 'Materiales') / 100).toStringAsFixed(2)}   |   Mano de obra: \$${(_categoryTotal(expenses, 'Mano de obra') / 100).toStringAsFixed(2)}   |   Otros: \$${(_categoryTotal(expenses, 'Otros') / 100).toStringAsFixed(2)}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'IVA incluido: \$${(_taxTotal(expenses) / 100).toStringAsFixed(2)}   |   Estado: ${_pdfSafe(project.status)}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
        ),
      ],
    ),
  );

  static void _styleHeader(Sheet sheet, int row, int columns) {
    final style = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString('#176B56'),
    );
    for (var column = 0; column < columns; column++) {
      sheet
              .cell(
                CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
              )
              .cellStyle =
          style;
    }
  }

  static int _total(List<LocalExpense> expenses) =>
      expenses.fold(0, (sum, expense) => sum + expense.totalCents);
  static int _taxTotal(List<LocalExpense> expenses) =>
      expenses.fold(0, (sum, expense) => sum + expense.taxCents);
  static List<LocalExpense> _expensesForProject(
    List<LocalExpense> expenses,
    String projectName,
  ) => expenses
      .where((expense) => expense.projectName == projectName)
      .toList(growable: false);
  static int _categoryTotal(List<LocalExpense> expenses, String group) =>
      expenses
          .where((expense) => expense.category.startsWith(group))
          .fold(0, (sum, expense) => sum + expense.totalCents);
  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  static String _dateTime(DateTime value) =>
      '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  static String _pdfSafe(String value) {
    const replacements = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'Á': 'A',
      'É': 'E',
      'Í': 'I',
      'Ó': 'O',
      'Ú': 'U',
      'ñ': 'n',
      'Ñ': 'N',
      'ü': 'u',
      'Ü': 'U',
      '·': ' - ',
    };
    var result = value;
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
  }

  static String _fileDate() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }
}
