import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/local_category.dart';
import '../data/local_database.dart';
import '../data/local_expense.dart';
import '../data/local_provider.dart';
import '../data/local_project.dart';
import '../data/local_labor.dart';

enum MobileSyncState { idle, syncing, synced, offline, error }

class FirebaseSyncService extends ChangeNotifier {
  FirebaseSyncService({LocalDatabase? database, FirebaseFirestore? firestore})
    : _database = database ?? LocalDatabase.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final LocalDatabase _database;
  final FirebaseFirestore _firestore;
  MobileSyncState _state = MobileSyncState.idle;
  String _error = '';

  MobileSyncState get state => _state;
  String get error => _error;
  bool get syncing => _state == MobileSyncState.syncing;

  String get label => switch (_state) {
    MobileSyncState.syncing => 'Sincronizando…',
    MobileSyncState.synced => 'Sincronizado',
    MobileSyncState.offline => 'Sin conexión · guardado local',
    MobileSyncState.error => 'No se pudo sincronizar',
    MobileSyncState.idle => 'Guardado en el celular',
  };

  Future<bool> sync(String uid, {bool forceCategories = false}) async {
    if (syncing) return false;
    _setState(MobileSyncState.syncing);
    try {
      final userRef = _firestore.collection('users').doc(uid);
      final user = await userRef.get();
      if (!user.exists) {
        await _createRemoteUser(uid, userRef);
      } else {
        await _pushQueue(uid);
        await _pullRemote(uid, forceCategories: forceCategories);
      }
      _setState(MobileSyncState.synced);
      return true;
    } on FirebaseException catch (exception) {
      _error = exception.message ?? exception.code;
      _setState(
        exception.code == 'unavailable' ||
                exception.code == 'network-request-failed'
            ? MobileSyncState.offline
            : MobileSyncState.error,
      );
      return false;
    } catch (exception) {
      _error = exception.toString();
      _setState(MobileSyncState.error);
      return false;
    }
  }

  Future<void> _createRemoteUser(
    String uid,
    DocumentReference<Map<String, dynamic>> userRef,
  ) async {
    final projects = await _database.getProjects();
    final expenses = await _database.getExpenses();
    final categories = await _database.getCategories();
    final providers = await _database.getProviders();
    final vatRate = await _database.getVatRatePercent();
    final workers = await _database.getWorkers();
    final workerRoles = await _database.getWorkerRoles();
    final attendance = await _database.getWorkerAttendance();
    final advances = await _database.getWorkerAdvances();
    final payments = await _database.getWorkerPayments();
    final projectIds = {
      for (final project in projects) project.name: project.clientId,
    };
    final batch = _firestore.batch();
    batch.set(userRef, {
      'uid': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    for (final project in projects) {
      batch.set(
        userRef.collection('projects').doc(project.clientId),
        _projectData(project.toMap()),
      );
    }
    for (final expense in expenses) {
      batch.set(
        userRef.collection('expenses').doc(expense.clientId),
        _expenseData(expense.toMap(), projectIds),
      );
    }
    for (final category in categories) {
      batch.set(userRef.collection('categories').doc(category.clientId), {
        'id': category.clientId,
        'name': category.fullName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    for (final provider in providers) {
      batch.set(userRef.collection('providers').doc(provider.clientId), {
        'id': provider.clientId,
        'name': provider.name,
        'contact': provider.contact,
        'phone': provider.phone,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    for (final item in workers) {
      batch.set(
        userRef.collection('workers').doc(item.clientId),
        _laborData(item.toMap()),
      );
    }
    for (final item in workerRoles) {
      batch.set(userRef.collection('workerRoles').doc(item.clientId), {
        'id': item.clientId,
        'name': item.name,
        'active': item.active,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    for (final item in attendance) {
      batch.set(
        userRef.collection('workerAttendance').doc(item.clientId),
        _laborData(item.toMap()),
      );
    }
    for (final item in advances) {
      batch.set(
        userRef.collection('workerAdvances').doc(item.clientId),
        _laborData(item.toMap()),
      );
    }
    for (final item in payments) {
      batch.set(
        userRef.collection('workerPayments').doc(item.clientId),
        _laborData(item.toMap()),
      );
    }
    batch.set(userRef.collection('settings').doc('general'), {
      'vatRate': vatRate,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    await _database.markAllSynced();
    await _database.setCategoriesFetchedAt(DateTime.now());
  }

  Future<void> _pushQueue(String uid) async {
    final userRef = _firestore.collection('users').doc(uid);
    final projects = await _database.getProjects();
    final projectIds = {
      for (final project in projects) project.name: project.clientId,
    };
    for (final item in await _database.getSyncQueue()) {
      if (item.operation == 'DELETE') {
        final reference = switch (item.entityType) {
          'project' => userRef.collection('projects').doc(item.entityId),
          'expense' => userRef.collection('expenses').doc(item.entityId),
          'category' => userRef.collection('categories').doc(item.entityId),
          'provider' => userRef.collection('providers').doc(item.entityId),
          'worker' => userRef.collection('workers').doc(item.entityId),
          'worker_role' => userRef.collection('workerRoles').doc(item.entityId),
          'worker_rate' => userRef.collection('workerRates').doc(item.entityId),
          'worker_attendance' =>
            userRef.collection('workerAttendance').doc(item.entityId),
          'worker_attendance_audit' =>
            userRef.collection('workerAttendanceAudit').doc(item.entityId),
          'worker_advance' =>
            userRef.collection('workerAdvances').doc(item.entityId),
          'worker_payment' =>
            userRef.collection('workerPayments').doc(item.entityId),
          _ => throw StateError(
            'Entidad de sincronización desconocida: ${item.entityType}',
          ),
        };
        await reference.delete();
        await _database.completeSyncItem(item);
        continue;
      }
      final DocumentReference<Map<String, dynamic>> reference;
      Map<String, dynamic>? data;
      switch (item.entityType) {
        case 'project':
          reference = userRef.collection('projects').doc(item.entityId);
          data = _projectData(item.payload);
        case 'expense':
          reference = userRef.collection('expenses').doc(item.entityId);
          data = _expenseData(item.payload, projectIds);
        case 'category':
          reference = userRef.collection('categories').doc(item.entityId);
          data = {
            'id': item.entityId,
            'name': '${item.payload['group_name']} · ${item.payload['name']}',
            'updatedAt': FieldValue.serverTimestamp(),
          };
        case 'provider':
          reference = userRef.collection('providers').doc(item.entityId);
          data = {
            'id': item.entityId,
            'name': item.payload['name'],
            'contact': item.payload['contact'] ?? '',
            'phone': item.payload['phone'] ?? '',
            'updatedAt': FieldValue.serverTimestamp(),
          };
        case 'setting':
          reference = userRef.collection('settings').doc('general');
          data = {
            'vatRate': double.tryParse('${item.payload['value']}') ?? 15,
            'updatedAt': FieldValue.serverTimestamp(),
          };
        case 'worker':
          reference = userRef.collection('workers').doc(item.entityId);
          data = _laborData(item.payload);
        case 'worker_role':
          reference = userRef.collection('workerRoles').doc(item.entityId);
          data = {
            'id': item.entityId,
            'name': item.payload['name'],
            'active': (item.payload['active'] as num?) == 1,
            'updatedAt': FieldValue.serverTimestamp(),
          };
        case 'worker_rate':
          reference = userRef.collection('workerRates').doc(item.entityId);
          data = _laborData(item.payload);
        case 'worker_attendance':
          reference = userRef.collection('workerAttendance').doc(item.entityId);
          data = _laborData(item.payload);
        case 'worker_attendance_audit':
          reference = userRef
              .collection('workerAttendanceAudit')
              .doc(item.entityId);
          data = {
            'id': item.entityId,
            'attendanceId': item.payload['attendance_id'],
            'snapshotJson': item.payload['snapshot_json'],
            'changedAt': item.payload['changed_at'],
            'updatedAt': FieldValue.serverTimestamp(),
          };
        case 'worker_advance':
          reference = userRef.collection('workerAdvances').doc(item.entityId);
          data = _laborData(item.payload);
        case 'worker_payment':
          reference = userRef.collection('workerPayments').doc(item.entityId);
          data = _laborData(item.payload);
        default:
          throw StateError(
            'Entidad de sincronización desconocida: ${item.entityType}',
          );
      }
      await reference.set(data, SetOptions(merge: true));
      await _database.completeSyncItem(item);
    }
  }

  Future<void> _pullRemote(String uid, {required bool forceCategories}) async {
    final userRef = _firestore.collection('users').doc(uid);
    final categoriesFetchedAt = await _database.getCategoriesFetchedAt();
    final shouldFetchCategories =
        forceCategories ||
        categoriesFetchedAt == null ||
        DateTime.now().difference(categoriesFetchedAt) >=
            const Duration(days: 1);
    final results = await Future.wait([
      userRef.collection('projects').get(),
      userRef.collection('expenses').get(),
      if (shouldFetchCategories) userRef.collection('categories').get(),
      userRef.collection('providers').get(),
      userRef.collection('settings').doc('general').get(),
      userRef.collection('workers').get(),
      userRef.collection('workerRoles').get(),
      userRef.collection('workerAttendance').get(),
      userRef.collection('workerAdvances').get(),
      userRef.collection('workerPayments').get(),
    ]);
    final projectSnapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final expenseSnapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;
    var resultIndex = 2;
    final categorySnapshot = shouldFetchCategories
        ? results[resultIndex++] as QuerySnapshot<Map<String, dynamic>>
        : null;
    final providerSnapshot =
        results[resultIndex++] as QuerySnapshot<Map<String, dynamic>>;
    final settingSnapshot =
        results[resultIndex] as DocumentSnapshot<Map<String, dynamic>>;
    final workerSnapshot =
        results[resultIndex + 1] as QuerySnapshot<Map<String, dynamic>>;
    final roleSnapshot =
        results[resultIndex + 2] as QuerySnapshot<Map<String, dynamic>>;
    final attendanceSnapshot =
        results[resultIndex + 3] as QuerySnapshot<Map<String, dynamic>>;
    final advanceSnapshot =
        results[resultIndex + 4] as QuerySnapshot<Map<String, dynamic>>;
    final paymentSnapshot =
        results[resultIndex + 5] as QuerySnapshot<Map<String, dynamic>>;
    final now = DateTime.now();

    final projects = projectSnapshot.docs.map((doc) {
      final data = doc.data();
      return LocalProject(
        clientId: doc.id,
        remoteId: doc.id,
        name: '${data['name'] ?? 'Proyecto'}',
        location: '${data['location'] ?? ''}',
        budgetCents: ((data['budget'] as num?) ?? 0).toDouble().times100,
        spentCents: 0,
        progress: ((data['progress'] as num?) ?? 0).toDouble(),
        status: '${data['status'] ?? 'ACTIVE'}',
        syncStatus: 'synced',
        updatedAt: _timestampDate(data['updatedAt']) ?? now,
      );
    }).toList();
    final projectNames = {
      for (final project in projects) project.clientId: project.name,
    };

    final expenses = expenseSnapshot.docs.map((doc) {
      final data = doc.data();
      final date = _localDate('${data['date'] ?? ''}') ?? now;
      final subtotal = ((data['subtotal'] as num?) ?? 0).toDouble().times100;
      final tax = ((data['tax'] as num?) ?? 0).toDouble().times100;
      final total = ((data['total'] as num?) ?? 0).toDouble().times100;
      return LocalExpense(
        clientId: doc.id,
        remoteId: doc.id,
        projectName: projectNames['${data['projectId']}'] ?? 'Proyecto',
        category: '${data['category'] ?? 'Otros · General'}',
        description: '${data['description'] ?? ''}',
        provider: '${data['provider'] ?? ''}',
        invoiceNumber: '${data['invoiceNumber'] ?? ''}',
        quantity: ((data['quantity'] as num?) ?? 1).toDouble(),
        unitPriceCents: ((data['unitPrice'] as num?) ?? 0).toDouble().times100,
        subtotalCents: subtotal,
        taxRateBps: ((((data['taxRate'] as num?) ?? 0).toDouble()) * 100)
            .round(),
        taxCents: tax,
        totalCents: total,
        expenseDate: date,
        createdAt: _timestampDate(data['createdAt']) ?? date,
        updatedAt: _timestampDate(data['updatedAt']) ?? now,
        syncStatus: 'synced',
      );
    }).toList();

    final categories = categorySnapshot == null
        ? await _database.getCategories()
        : categorySnapshot.docs.map((doc) {
            final fullName = '${doc.data()['name'] ?? 'Otros · General'}';
            final parts = fullName.split(' · ');
            return LocalCategory(
              clientId: doc.id,
              remoteId: doc.id,
              name: parts.length > 1 ? parts.sublist(1).join(' · ') : fullName,
              groupName: parts.length > 1 ? parts.first : 'Otros',
              syncStatus: 'synced',
              updatedAt: _timestampDate(doc.data()['updatedAt']) ?? now,
            );
          }).toList();

    final providers = providerSnapshot.docs.map((doc) {
      final data = doc.data();
      return LocalProvider(
        clientId: doc.id,
        remoteId: doc.id,
        name: '${data['name'] ?? 'Proveedor'}',
        contact: '${data['contact'] ?? ''}',
        phone: '${data['phone'] ?? ''}',
        syncStatus: 'synced',
        updatedAt: _timestampDate(data['updatedAt']) ?? now,
      );
    }).toList();

    await _database.replaceDemoWithRemote(
      projects: projects,
      expenses: expenses,
      categories: categories,
      providers: providers,
      vatRatePercent: ((settingSnapshot.data()?['vatRate'] as num?) ?? 15)
          .toDouble(),
    );
    await _database.replaceLaborRemote(
      roles: roleSnapshot.docs.isEmpty
          ? await _database.getWorkerRoles()
          : roleSnapshot.docs
                .map(
                  (d) => LocalWorkerRole(
                    clientId: d.id,
                    name: _s(d.data(), 'name', 'Otros'),
                    active: d.data()['active'] != false,
                    syncStatus: 'synced',
                    updatedAt: _timestampDate(d.data()['updatedAt']) ?? now,
                  ),
                )
                .toList(),
      workers: workerSnapshot.docs
          .map((d) => _remoteWorker(d.id, d.data(), now))
          .toList(),
      attendance: attendanceSnapshot.docs
          .map((d) => _remoteAttendance(d.id, d.data(), now))
          .toList(),
      advances: advanceSnapshot.docs
          .map((d) => _remoteAdvance(d.id, d.data(), now))
          .toList(),
      payments: paymentSnapshot.docs
          .map((d) => _remotePayment(d.id, d.data(), now))
          .toList(),
    );
    if (shouldFetchCategories) {
      await _database.setCategoriesFetchedAt(now);
    }
  }

  Map<String, dynamic> _projectData(Map<String, Object?> data) => {
    'id': data['client_id'],
    'name': data['name'],
    'location': data['location'],
    'budget': ((data['budget_cents'] as num?) ?? 0) / 100,
    'progress': ((data['progress'] as num?) ?? 0).toDouble(),
    'status': data['status'] ?? 'ACTIVE',
    'updatedAt': FieldValue.serverTimestamp(),
  };

  Map<String, dynamic> _expenseData(
    Map<String, Object?> data,
    Map<String, String> projectIds,
  ) => {
    'id': data['client_id'],
    'projectId': projectIds['${data['project_name']}'] ?? '',
    'category': data['category'],
    'description': data['description'],
    'provider': data['provider'] ?? '',
    'invoiceNumber': data['invoice_number'] ?? '',
    'quantity': ((data['quantity'] as num?) ?? 1).toDouble(),
    'unitPrice': ((data['unit_price_cents'] as num?) ?? 0) / 100,
    'subtotal': ((data['subtotal_cents'] as num?) ?? 0) / 100,
    'taxRate': ((data['tax_rate_bps'] as num?) ?? 0) / 100,
    'tax': ((data['tax_cents'] as num?) ?? 0) / 100,
    'total': ((data['total_cents'] as num?) ?? 0) / 100,
    'date': _dateOnly(DateTime.parse('${data['expense_date']}').toLocal()),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  Map<String, dynamic> _laborData(Map<String, Object?> source) {
    if (source.containsKey('full_name')) {
      return {
        'id': source['client_id'],
        'fullName': source['full_name'],
        'nationalId': source['national_id'],
        'phone': source['phone'],
        'roleId': source['role_id'],
        'defaultRate': (source['default_rate_cents'] as num) / 100,
        'startDate': source['start_date'],
        'status': source['status'],
        'notes': source['notes'],
        'projectIds': '${source['project_ids'] ?? ''}'
            .split(',')
            .where((e) => e.isNotEmpty)
            .toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
    }
    if (source.containsKey('attendance_type')) {
      return {
        'id': source['client_id'],
        'workerId': source['worker_id'],
        'projectId': source['project_id'],
        'date': source['attendance_date'],
        'status': source['attendance_type'],
        'appliedRate': (source['applied_rate_cents'] as num) / 100,
        'allocation': (source['allocation_bps'] as num) / 10000,
        'earned': (source['earned_cents'] as num) / 100,
        'notes': source['notes'],
        'revision': source['revision'],
        'updatedAt': FieldValue.serverTimestamp(),
      };
    }
    if (source.containsKey('advance_date')) {
      return {
        'id': source['client_id'],
        'workerId': source['worker_id'],
        'projectId': source['project_id'],
        'date': source['advance_date'],
        'amount': (source['amount_cents'] as num) / 100,
        'method': source['method'],
        'reference': source['reference'],
        'notes': source['notes'],
        'appliedAmount': (source['applied_cents'] as num) / 100,
        'updatedAt': FieldValue.serverTimestamp(),
      };
    }
    if (source.containsKey('payment_date')) {
      return {
        'id': source['client_id'],
        'workerId': source['worker_id'],
        'projectId': source['project_id'],
        'periodStart': source['period_start'],
        'periodEnd': source['period_end'],
        'date': source['payment_date'],
        'amount': (source['amount_cents'] as num) / 100,
        'method': source['method'],
        'reference': source['reference'],
        'notes': source['notes'],
        'updatedAt': FieldValue.serverTimestamp(),
      };
    }
    if (source.containsKey('daily_rate_cents')) {
      return {
        'id': source['client_id'],
        'workerId': source['worker_id'],
        'projectId': source['project_id'],
        'dailyRate': (source['daily_rate_cents'] as num) / 100,
        'validFrom': source['valid_from'],
        'validTo': source['valid_to'] ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      };
    }
    final data = <String, dynamic>{
      'id': source['client_id'],
      'updatedAt': FieldValue.serverTimestamp(),
    };
    source.forEach((key, value) {
      if (![
        'client_id',
        'remote_id',
        'sync_status',
        'updated_at',
        'is_deleted',
      ].contains(key)) {
        data[_camel(key)] = value;
      }
    });
    return data;
  }

  String _camel(String key) {
    final p = key.split('_');
    return p.first +
        p.skip(1).map((e) => e[0].toUpperCase() + e.substring(1)).join();
  }

  String _s(Map<String, dynamic> d, String key, [String fallback = '']) =>
      '${d[key] ?? fallback}';
  int _c(Map<String, dynamic> d, String key) =>
      (((d[key] as num?) ?? 0).toDouble() * 100).round();
  LocalWorker _remoteWorker(String id, Map<String, dynamic> d, DateTime now) =>
      LocalWorker(
        clientId: id,
        remoteId: id,
        fullName: _s(d, 'fullName'),
        nationalId: _s(d, 'nationalId'),
        phone: _s(d, 'phone'),
        roleId: _s(d, 'roleId', 'otros'),
        defaultRateCents: _c(d, 'defaultRate'),
        startDate: _localDate(_s(d, 'startDate')) ?? now,
        status: _s(d, 'status', 'ACTIVE'),
        notes: _s(d, 'notes'),
        projectIds: (d['projectIds'] as List? ?? const [])
            .map((e) => '$e')
            .toList(),
        syncStatus: 'synced',
        updatedAt: _timestampDate(d['updatedAt']) ?? now,
      );
  LocalAttendance _remoteAttendance(
    String id,
    Map<String, dynamic> d,
    DateTime now,
  ) {
    final type = _s(d, 'status', 'ABSENT');
    return LocalAttendance(
      clientId: id,
      workerId: _s(d, 'workerId'),
      projectId: _s(d, 'projectId'),
      date: _localDate(_s(d, 'date')) ?? now,
      kind: AttendanceKind.values.firstWhere(
        (e) => e.name.toUpperCase() == type,
        orElse: () => AttendanceKind.absent,
      ),
      appliedRateCents: _c(d, 'appliedRate'),
      allocationBps: ((((d['allocation'] as num?) ?? 1).toDouble()) * 10000)
          .round(),
      earnedCents: _c(d, 'earned'),
      notes: _s(d, 'notes'),
      revision: ((d['revision'] as num?) ?? 1).toInt(),
      syncStatus: 'synced',
      updatedAt: _timestampDate(d['updatedAt']) ?? now,
    );
  }

  LocalAdvance _remoteAdvance(
    String id,
    Map<String, dynamic> d,
    DateTime now,
  ) => LocalAdvance(
    clientId: id,
    workerId: _s(d, 'workerId'),
    projectId: _s(d, 'projectId'),
    date: _localDate(_s(d, 'date')) ?? now,
    amountCents: _c(d, 'amount'),
    method: _s(d, 'method', 'CASH'),
    reference: _s(d, 'reference'),
    notes: _s(d, 'notes'),
    appliedCents: _c(d, 'appliedAmount'),
    syncStatus: 'synced',
    updatedAt: _timestampDate(d['updatedAt']) ?? now,
  );
  LocalWorkerPayment _remotePayment(
    String id,
    Map<String, dynamic> d,
    DateTime now,
  ) => LocalWorkerPayment(
    clientId: id,
    workerId: _s(d, 'workerId'),
    projectId: _s(d, 'projectId'),
    periodStart: _localDate(_s(d, 'periodStart')) ?? now,
    periodEnd: _localDate(_s(d, 'periodEnd')) ?? now,
    date: _localDate(_s(d, 'date')) ?? now,
    amountCents: _c(d, 'amount'),
    method: _s(d, 'method', 'CASH'),
    reference: _s(d, 'reference'),
    notes: _s(d, 'notes'),
    syncStatus: 'synced',
    updatedAt: _timestampDate(d['updatedAt']) ?? now,
  );

  DateTime? _timestampDate(Object? value) =>
      value is Timestamp ? value.toDate().toLocal() : null;

  DateTime? _localDate(String value) {
    final parts = value.split('-');
    if (parts.length != 3) return null;
    return DateTime(
      int.tryParse(parts[0]) ?? 0,
      int.tryParse(parts[1]) ?? 1,
      int.tryParse(parts[2]) ?? 1,
    );
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  void _setState(MobileSyncState value) {
    _state = value;
    if (value != MobileSyncState.error && value != MobileSyncState.offline) {
      _error = '';
    }
    notifyListeners();
  }
}

extension on double {
  int get times100 => (this * 100).round();
}
