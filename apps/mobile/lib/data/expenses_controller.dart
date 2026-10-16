import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_database.dart';
import 'local_category.dart';
import 'local_expense.dart';
import 'local_provider.dart';
import 'local_project.dart';
import 'local_labor.dart';

class ExpensesController extends ChangeNotifier {
  ExpensesController({LocalDatabase? database})
    : _database = database ?? LocalDatabase.instance;

  final LocalDatabase _database;
  List<LocalExpense> _expenses = const [];
  List<LocalProject> _projects = const [];
  List<LocalCategory> _categories = const [];
  List<LocalProvider> _providers = const [];
  List<LocalWorker> _workers = const [];
  List<LocalWorkerRole> _workerRoles = const [];
  List<LocalAttendance> _attendance = const [];
  List<LocalAdvance> _advances = const [];
  List<LocalWorkerPayment> _workerPayments = const [];
  int _pendingSyncCount = 0;
  double _vatRatePercent = 15;
  String _projectFilter = 'ACTIVE';
  bool _loading = true;
  DateTime? _categoriesFetchedAt;
  Future<void> Function()? onLocalChange;

  List<LocalExpense> get expenses => _expenses;
  List<LocalProject> get projects => _projects;
  List<LocalCategory> get categories => _categories;
  List<LocalProvider> get providers => _providers;
  List<LocalWorker> get workers => _workers;
  List<LocalWorkerRole> get workerRoles => _workerRoles;
  List<LocalAttendance> get attendance => _attendance;
  List<LocalAdvance> get advances => _advances;
  List<LocalWorkerPayment> get workerPayments => _workerPayments;
  List<LocalWorker> get activeWorkers =>
      _workers.where((w) => w.status == 'ACTIVE').toList();
  int get laborEarnedCents => _attendance.fold(0, (s, e) => s + e.earnedCents);
  LaborSummary get laborSummary =>
      summarizeLabor(_attendance, _advances, _workerPayments);
  int projectExecutedCents(LocalProject project) =>
      project.spentCents +
      _attendance
          .where((a) => a.projectId == project.clientId)
          .fold(0, (s, a) => s + a.earnedCents);
  int get pendingSyncCount => _pendingSyncCount;
  double get vatRatePercent => _vatRatePercent;
  String get projectFilter => _projectFilter;
  bool get loading => _loading;
  DateTime? get categoriesFetchedAt => _categoriesFetchedAt;
  List<LocalProject> get activeProjects =>
      _projects.where((project) => project.status == 'ACTIVE').toList();
  List<LocalProject> get filteredProjects => _projectFilter == 'ALL'
      ? _projects
      : _projects.where((project) => project.status == _projectFilter).toList();
  List<LocalExpense> get activeExpenses {
    final names = activeProjects.map((project) => project.name).toSet();
    return _expenses
        .where((expense) => names.contains(expense.projectName))
        .toList();
  }

  List<LocalExpense> get filteredExpenses {
    final names = filteredProjects.map((project) => project.name).toSet();
    return _expenses
        .where((expense) => names.contains(expense.projectName))
        .toList();
  }

  Future<void> initialize() async {
    await reload();
  }

  Future<void> reload() async {
    _loading = true;
    notifyListeners();
    _expenses = await _database.getExpenses();
    _projects = await _database.getProjects();
    _categories = await _database.getCategories();
    _providers = await _database.getProviders();
    _workers = await _database.getWorkers();
    _workerRoles = await _database.getWorkerRoles();
    _attendance = await _database.getWorkerAttendance();
    _advances = await _database.getWorkerAdvances();
    _workerPayments = await _database.getWorkerPayments();
    _categoriesFetchedAt = await _database.getCategoriesFetchedAt();
    _vatRatePercent = await _database.getVatRatePercent();
    _pendingSyncCount = await _database.pendingSyncCount();
    _loading = false;
    notifyListeners();
  }

  Future<void> addExpense({
    required String projectName,
    required String category,
    required String description,
    required String provider,
    required String invoiceNumber,
    required double quantity,
    required int unitPriceCents,
    required int taxRateBps,
    required DateTime expenseDate,
  }) async {
    final now = DateTime.now();
    final subtotalCents = (quantity * unitPriceCents).round();
    final taxCents = (subtotalCents * taxRateBps / 10000).round();
    final expense = LocalExpense(
      clientId: 'expense-${now.microsecondsSinceEpoch}',
      projectName: projectName,
      category: category,
      description: description,
      provider: provider,
      invoiceNumber: invoiceNumber,
      quantity: quantity,
      unitPriceCents: unitPriceCents,
      subtotalCents: subtotalCents,
      taxRateBps: taxRateBps,
      taxCents: taxCents,
      totalCents: subtotalCents + taxCents,
      expenseDate: expenseDate,
      createdAt: now,
      updatedAt: now,
      syncStatus: 'pending',
    );
    await _database.insertExpense(expense);
    await reload();
    _scheduleSync();
  }

  Future<void> updateExpense({
    required LocalExpense previous,
    required String projectName,
    required String category,
    required String description,
    required String provider,
    required String invoiceNumber,
    required double quantity,
    required int unitPriceCents,
    required int taxRateBps,
    required DateTime expenseDate,
  }) async {
    final now = DateTime.now();
    final subtotalCents = (quantity * unitPriceCents).round();
    final taxCents = (subtotalCents * taxRateBps / 10000).round();
    final expense = LocalExpense(
      clientId: previous.clientId,
      remoteId: previous.remoteId,
      projectName: projectName,
      category: category,
      description: description,
      provider: provider,
      invoiceNumber: invoiceNumber,
      quantity: quantity,
      unitPriceCents: unitPriceCents,
      subtotalCents: subtotalCents,
      taxRateBps: taxRateBps,
      taxCents: taxCents,
      totalCents: subtotalCents + taxCents,
      expenseDate: expenseDate,
      createdAt: previous.createdAt,
      updatedAt: now,
      syncStatus: 'pending',
    );
    await _database.updateExpense(expense, previous: previous);
    await reload();
    _scheduleSync();
  }

  Future<void> deleteExpense(LocalExpense expense) async {
    await _database.softDeleteExpense(expense);
    await reload();
    _scheduleSync();
  }

  Future<void> addProject({
    required String name,
    required String location,
    required int budgetCents,
  }) async {
    final now = DateTime.now();
    await _database.insertProject(
      LocalProject(
        clientId: 'project-${now.microsecondsSinceEpoch}',
        name: name,
        location: location,
        budgetCents: budgetCents,
        spentCents: 0,
        progress: 0,
        status: 'ACTIVE',
        syncStatus: 'pending',
        updatedAt: now,
      ),
    );
    await reload();
    _scheduleSync();
  }

  Future<void> updateProject({
    required LocalProject previous,
    required String name,
    required String location,
    required int budgetCents,
    required String status,
  }) async {
    final updated = LocalProject(
      clientId: previous.clientId,
      remoteId: previous.remoteId,
      name: name,
      location: location,
      budgetCents: budgetCents,
      spentCents: previous.spentCents,
      progress: previous.progress,
      status: status,
      syncStatus: 'pending',
      updatedAt: DateTime.now(),
    );
    await _database.updateProject(updated, previousName: previous.name);
    await reload();
    _scheduleSync();
  }

  Future<void> changeProjectStatus(LocalProject project, String status) async {
    await updateProject(
      previous: project,
      name: project.name,
      location: project.location,
      budgetCents: project.budgetCents,
      status: status,
    );
  }

  Future<bool> deleteProject(LocalProject project) async {
    final deleted = await _database.softDeleteProject(project);
    if (!deleted) return false;
    await reload();
    _scheduleSync();
    return true;
  }

  void setProjectFilter(String filter) {
    _projectFilter = filter;
    notifyListeners();
  }

  Future<void> setVatRatePercent(double rate) async {
    await _database.setVatRatePercent(rate);
    await reload();
    _scheduleSync();
  }

  Future<void> addCategory({
    required String name,
    required String groupName,
  }) async {
    final now = DateTime.now();
    await _database.insertCategory(
      LocalCategory(
        clientId: 'category-${now.microsecondsSinceEpoch}',
        name: name,
        groupName: groupName,
        syncStatus: 'pending',
        updatedAt: now,
      ),
    );
    await reload();
    _scheduleSync();
  }

  Future<void> updateCategory({
    required LocalCategory previous,
    required String name,
    required String groupName,
  }) async {
    await _database.updateCategory(
      LocalCategory(
        clientId: previous.clientId,
        remoteId: previous.remoteId,
        name: name,
        groupName: groupName,
        syncStatus: 'pending',
        updatedAt: DateTime.now(),
      ),
    );
    await reload();
    _scheduleSync();
  }

  Future<void> deleteCategory(LocalCategory category) async {
    await _database.softDeleteCategory(category);
    await reload();
    _scheduleSync();
  }

  Future<void> addProvider({
    required String name,
    required String contact,
    required String phone,
  }) async {
    final now = DateTime.now();
    await _database.insertProvider(
      LocalProvider(
        clientId: 'provider-${now.microsecondsSinceEpoch}',
        name: name,
        contact: contact,
        phone: phone,
        syncStatus: 'pending',
        updatedAt: now,
      ),
    );
    await reload();
    _scheduleSync();
  }

  Future<void> updateProvider({
    required LocalProvider previous,
    required String name,
    required String contact,
    required String phone,
  }) async {
    await _database.updateProvider(
      LocalProvider(
        clientId: previous.clientId,
        remoteId: previous.remoteId,
        name: name,
        contact: contact,
        phone: phone,
        syncStatus: 'pending',
        updatedAt: DateTime.now(),
      ),
    );
    await reload();
    _scheduleSync();
  }

  Future<void> deleteProvider(LocalProvider provider) async {
    await _database.softDeleteProvider(provider);
    await reload();
    _scheduleSync();
  }

  Future<void> saveWorker({
    LocalWorker? previous,
    required String fullName,
    required String nationalId,
    required String phone,
    required String roleId,
    required int defaultRateCents,
    required DateTime startDate,
    required String notes,
    required List<String> projectIds,
  }) async {
    final now = DateTime.now();
    await _database.saveWorker(
      LocalWorker(
        clientId: previous?.clientId ?? 'worker-${now.microsecondsSinceEpoch}',
        remoteId: previous?.remoteId,
        fullName: fullName,
        nationalId: nationalId,
        phone: phone,
        roleId: roleId,
        defaultRateCents: defaultRateCents,
        startDate: startDate,
        status: previous?.status ?? 'ACTIVE',
        notes: notes,
        projectIds: projectIds,
        syncStatus: 'pending',
        updatedAt: now,
      ),
    );
    await reload();
    _scheduleSync();
  }

  Future<void> addWorkerRole(String name) async {
    final now = DateTime.now();
    await _database.saveWorkerRole(
      LocalWorkerRole(
        clientId: 'role-${now.microsecondsSinceEpoch}',
        name: name.trim(),
        active: true,
        syncStatus: 'pending',
        updatedAt: now,
      ),
    );
    await reload();
    _scheduleSync();
  }

  Future<void> toggleWorker(LocalWorker worker) async {
    final now = DateTime.now();
    await _database.saveWorker(
      LocalWorker(
        clientId: worker.clientId,
        remoteId: worker.remoteId,
        fullName: worker.fullName,
        nationalId: worker.nationalId,
        phone: worker.phone,
        roleId: worker.roleId,
        defaultRateCents: worker.defaultRateCents,
        startDate: worker.startDate,
        status: worker.status == 'ACTIVE' ? 'INACTIVE' : 'ACTIVE',
        notes: worker.notes,
        projectIds: worker.projectIds,
        syncStatus: 'pending',
        updatedAt: now,
      ),
    );
    await reload();
    _scheduleSync();
  }

  Future<void> saveAttendance({
    required String workerId,
    required String projectId,
    required DateTime date,
    required AttendanceKind kind,
    required int appliedRateCents,
    required int allocationBps,
    required String notes,
  }) async {
    final now = DateTime.now();
    final dateKey =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    await _database.saveAttendance(
      LocalAttendance(
        clientId: '${workerId}_${projectId}_$dateKey',
        workerId: workerId,
        projectId: projectId,
        date: date,
        kind: kind,
        appliedRateCents: appliedRateCents,
        allocationBps: allocationBps,
        earnedCents: calculateLaborCents(
          dailyRateCents: appliedRateCents,
          attendance: kind,
          allocation: allocationBps / 10000,
        ),
        notes: notes,
        revision: 1,
        syncStatus: 'pending',
        updatedAt: now,
      ),
    );
    await reload();
    _scheduleSync();
  }

  Future<void> saveAdvance({
    required String workerId,
    required String projectId,
    required DateTime date,
    required int amountCents,
    required String method,
    required String reference,
    required String notes,
  }) async {
    final now = DateTime.now();
    await _database.saveAdvance(
      LocalAdvance(
        clientId: 'advance-${now.microsecondsSinceEpoch}',
        workerId: workerId,
        projectId: projectId,
        date: date,
        amountCents: amountCents,
        method: method,
        reference: reference,
        notes: notes,
        appliedCents: 0,
        syncStatus: 'pending',
        updatedAt: now,
      ),
    );
    await reload();
    _scheduleSync();
  }

  Future<void> saveWorkerPayment({
    required String workerId,
    required String projectId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int amountCents,
    required String method,
    required String reference,
    required String notes,
  }) async {
    if (reference.isNotEmpty &&
        _workerPayments.any(
          (p) => p.workerId == workerId && p.reference == reference,
        )) {
      throw StateError('Pago duplicado');
    }
    final now = DateTime.now();
    await _database.saveWorkerPayment(
      LocalWorkerPayment(
        clientId: 'payment-${now.microsecondsSinceEpoch}',
        workerId: workerId,
        projectId: projectId,
        periodStart: periodStart,
        periodEnd: periodEnd,
        date: now,
        amountCents: amountCents,
        method: method,
        reference: reference,
        notes: notes,
        syncStatus: 'pending',
        updatedAt: now,
      ),
    );
    await reload();
    _scheduleSync();
  }

  void _scheduleSync() {
    final callback = onLocalChange;
    if (callback != null) unawaited(callback());
  }
}
