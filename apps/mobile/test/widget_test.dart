import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:gastos_mobile/data/local_expense.dart';
import 'package:gastos_mobile/data/local_project.dart';
import 'package:gastos_mobile/main.dart';

void main() {
  testWidgets('muestra el dashboard financiero', (tester) async {
    await pumpDashboard(tester);
    expect(find.text('Buenos días, Marcelo'), findsOneWidget);
    expect(find.text('Presupuesto total'), findsOneWidget);
    expect(find.text('Registrar gasto'), findsWidgets);
  });

  testWidgets('expone creación de proyectos y exportaciones', (tester) async {
    await pumpDashboard(tester);

    await tester.tap(find.text('Proyectos').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Nuevo proyecto'), findsOneWidget);

    await tester.tap(find.text('Reportes').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Exportar PDF'), findsOneWidget);
    expect(find.text('Exportar Excel'), findsOneWidget);
  });

  testWidgets('pide confirmación antes de eliminar un gasto', (tester) async {
    final now = DateTime.utc(2026, 8, 16);
    final expense = LocalExpense(
      clientId: 'expense-confirmation',
      projectName: 'Casa Prueba',
      category: 'Materiales · Cemento',
      description: 'Compra de cemento',
      provider: 'Disensa',
      quantity: 1,
      unitPriceCents: 1000,
      subtotalCents: 1000,
      taxRateBps: 0,
      taxCents: 0,
      totalCents: 1000,
      expenseDate: now,
      createdAt: now,
      updatedAt: now,
      syncStatus: 'pending',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LocalExpenseTile(expense: expense)),
      ),
    );

    await tester.tap(find.byTooltip('Opciones del gasto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();

    expect(find.text('¿Eliminar este gasto?'), findsOneWidget);
    expect(find.text('Sí, eliminar'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Eliminar este gasto?'), findsNothing);
  });

  testWidgets('expone la eliminación protegida de proyectos', (tester) async {
    final project = LocalProject(
      clientId: 'project-delete-option',
      name: 'Proyecto sin gastos',
      location: 'Guayaquil',
      budgetCents: 100000,
      spentCents: 0,
      progress: 0,
      status: 'ACTIVE',
      syncStatus: 'synced',
      updatedAt: DateTime.utc(2026, 9, 19),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LocalProjectCard(project: project)),
      ),
    );

    await tester.tap(find.byTooltip('Opciones del proyecto'));
    await tester.pumpAndSettle();

    expect(find.text('Eliminar proyecto'), findsOneWidget);
  });

  testWidgets('solicita crear un PIN local después del primer acceso', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PinSetupPage(
          uid: 'usuario-prueba',
          email: 'prueba@obraflow.test',
          onComplete: () {},
          onSignOut: () async {},
        ),
      ),
    );

    expect(find.text('Protege ObraFlow'), findsOneWidget);
    expect(find.text('Guardar y continuar'), findsOneWidget);
  });

  testWidgets('muestra acceso con Google en la pantalla inicial', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);
  });

  testWidgets('valida el PIN antes de intentar desbloquear', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UnlockPage(
          uid: 'usuario-prueba',
          email: 'prueba@obraflow.test',
          onUnlocked: () {},
          onSignOut: () async {},
        ),
      ),
    );

    await tester.tap(find.text('Desbloquear con PIN'));
    await tester.pump();
    expect(find.text('Ingresa tu PIN de 4 a 6 números.'), findsOneWidget);
  });
}

Future<void> pumpDashboard(WidgetTester tester) => tester.pumpWidget(
  MaterialApp(
    theme: appTheme(Brightness.light),
    home: AppShell(onTheme: () {}, onSync: () async {}, onSignOut: () async {}),
  ),
);
