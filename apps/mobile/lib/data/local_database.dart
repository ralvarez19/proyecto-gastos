import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'local_expense.dart';
import 'local_category.dart';
import 'local_provider.dart';
import 'local_project.dart';
import 'local_labor.dart';

class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final folder = await getDatabasesPath();
    _database = await openDatabase(
      p.join(folder, 'obraflow.db'),
      version: 6,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    return _database!;
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE projects (
        client_id TEXT PRIMARY KEY,
        remote_id TEXT,
        name TEXT NOT NULL,
        location TEXT NOT NULL,
        budget_cents INTEGER NOT NULL CHECK (budget_cents >= 0),
        spent_cents INTEGER NOT NULL CHECK (spent_cents >= 0),
        progress REAL NOT NULL CHECK (progress >= 0 AND progress <= 1),
        status TEXT NOT NULL DEFAULT 'ACTIVE',
        sync_status TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE expenses (
        client_id TEXT PRIMARY KEY,
        remote_id TEXT,
        project_name TEXT NOT NULL,
        category TEXT NOT NULL,
        description TEXT NOT NULL,
        provider TEXT NOT NULL DEFAULT '',
        invoice_number TEXT NOT NULL DEFAULT '',
        quantity REAL NOT NULL CHECK (quantity > 0),
        unit_price_cents INTEGER NOT NULL CHECK (unit_price_cents >= 0),
        subtotal_cents INTEGER NOT NULL CHECK (subtotal_cents >= 0),
        tax_rate_bps INTEGER NOT NULL DEFAULT 0 CHECK (tax_rate_bps >= 0),
        tax_cents INTEGER NOT NULL DEFAULT 0 CHECK (tax_cents >= 0),
        total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
        expense_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT
      )
    ''');
    await _createCategoriesTable(db);
    await _createProvidersTable(db);
    await _createSettingsTable(db);
    await _createLaborSchema(db);
    await db.execute(
      'CREATE INDEX idx_expenses_date ON expenses(expense_date DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_expenses_sync ON expenses(sync_status, updated_at)',
    );
    await db.execute('CREATE UNIQUE INDEX idx_projects_name ON projects(name)');
    await _seedInitialActualData(db);
    await _seedSettings(db);
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _createCategoriesTable(db);
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_projects_name ON projects(name)',
      );
      await _seedCategories(db);
    }
    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE projects ADD COLUMN status TEXT NOT NULL DEFAULT 'ACTIVE'",
      );
      await db.execute(
        'ALTER TABLE expenses ADD COLUMN subtotal_cents INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE expenses ADD COLUMN tax_rate_bps INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE expenses ADD COLUMN tax_cents INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'UPDATE expenses SET subtotal_cents = total_cents WHERE subtotal_cents = 0',
      );
      await _createSettingsTable(db);
      await _seedSettings(db);
    }
    if (oldVersion < 4) {
      await _createProvidersTable(db);
    }
    if (oldVersion < 5) {
      await db.execute(
        "ALTER TABLE expenses ADD COLUMN invoice_number TEXT NOT NULL DEFAULT ''",
      );
      await _seedInitialActualData(db);
    }
    if (oldVersion < 6) {
      await _createLaborSchema(db);
    }
  }

  Future<void> _createLaborSchema(Database db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS worker_roles (
      client_id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, active INTEGER NOT NULL DEFAULT 1,
      sync_status TEXT NOT NULL, updated_at TEXT NOT NULL, is_deleted INTEGER NOT NULL DEFAULT 0)''',
    );
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS workers (
      client_id TEXT PRIMARY KEY, remote_id TEXT, full_name TEXT NOT NULL, national_id TEXT NOT NULL DEFAULT '',
      phone TEXT NOT NULL DEFAULT '', role_id TEXT NOT NULL, default_rate_cents INTEGER NOT NULL CHECK(default_rate_cents >= 0),
      start_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'ACTIVE', notes TEXT NOT NULL DEFAULT '', project_ids TEXT NOT NULL DEFAULT '',
      sync_status TEXT NOT NULL, updated_at TEXT NOT NULL, is_deleted INTEGER NOT NULL DEFAULT 0)''',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS worker_assignments (
      client_id TEXT PRIMARY KEY, worker_id TEXT NOT NULL, project_id TEXT NOT NULL, valid_from TEXT NOT NULL,
      valid_to TEXT, sync_status TEXT NOT NULL, updated_at TEXT NOT NULL, is_deleted INTEGER NOT NULL DEFAULT 0,
      UNIQUE(worker_id, project_id, valid_from))''');
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS worker_rates (
      client_id TEXT PRIMARY KEY, worker_id TEXT NOT NULL, project_id TEXT NOT NULL DEFAULT '', daily_rate_cents INTEGER NOT NULL,
      valid_from TEXT NOT NULL, valid_to TEXT, sync_status TEXT NOT NULL, updated_at TEXT NOT NULL, is_deleted INTEGER NOT NULL DEFAULT 0)''',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS worker_attendance (
      client_id TEXT PRIMARY KEY, worker_id TEXT NOT NULL, project_id TEXT NOT NULL, attendance_date TEXT NOT NULL,
      attendance_type TEXT NOT NULL, applied_rate_cents INTEGER NOT NULL, allocation_bps INTEGER NOT NULL DEFAULT 10000,
      earned_cents INTEGER NOT NULL, notes TEXT NOT NULL DEFAULT '', revision INTEGER NOT NULL DEFAULT 1,
      sync_status TEXT NOT NULL, updated_at TEXT NOT NULL, is_deleted INTEGER NOT NULL DEFAULT 0,
      UNIQUE(worker_id, project_id, attendance_date))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS worker_attendance_audit (
      client_id TEXT PRIMARY KEY, attendance_id TEXT NOT NULL, snapshot_json TEXT NOT NULL,
      changed_at TEXT NOT NULL, sync_status TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS worker_advances (
      client_id TEXT PRIMARY KEY, worker_id TEXT NOT NULL, project_id TEXT NOT NULL DEFAULT '', advance_date TEXT NOT NULL,
      amount_cents INTEGER NOT NULL CHECK(amount_cents > 0), method TEXT NOT NULL, reference TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '', applied_cents INTEGER NOT NULL DEFAULT 0, sync_status TEXT NOT NULL,
      updated_at TEXT NOT NULL, is_deleted INTEGER NOT NULL DEFAULT 0)''');
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS payroll_periods (
      client_id TEXT PRIMARY KEY, start_date TEXT NOT NULL, end_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'OPEN',
      closed_at TEXT, reopened_at TEXT, audit_note TEXT NOT NULL DEFAULT '', sync_status TEXT NOT NULL,
      updated_at TEXT NOT NULL, is_deleted INTEGER NOT NULL DEFAULT 0, UNIQUE(start_date,end_date))''',
    );
    await db.execute('''CREATE TABLE IF NOT EXISTS payroll_items (
      client_id TEXT PRIMARY KEY, period_id TEXT NOT NULL, worker_id TEXT NOT NULL, project_id TEXT NOT NULL DEFAULT '',
      earned_cents INTEGER NOT NULL, advance_cents INTEGER NOT NULL, payment_cents INTEGER NOT NULL, pending_cents INTEGER NOT NULL,
      sync_status TEXT NOT NULL, updated_at TEXT NOT NULL, is_deleted INTEGER NOT NULL DEFAULT 0,
      UNIQUE(period_id,worker_id,project_id))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS worker_payments (
      client_id TEXT PRIMARY KEY, worker_id TEXT NOT NULL, project_id TEXT NOT NULL DEFAULT '', period_start TEXT NOT NULL,
      period_end TEXT NOT NULL, payment_date TEXT NOT NULL, amount_cents INTEGER NOT NULL CHECK(amount_cents > 0),
      method TEXT NOT NULL, reference TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '', sync_status TEXT NOT NULL,
      updated_at TEXT NOT NULL, is_deleted INTEGER NOT NULL DEFAULT 0)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS labor_cost_allocations (
      client_id TEXT PRIMARY KEY, attendance_id TEXT NOT NULL, project_id TEXT NOT NULL, allocation_bps INTEGER NOT NULL,
      cost_cents INTEGER NOT NULL, sync_status TEXT NOT NULL, updated_at TEXT NOT NULL, is_deleted INTEGER NOT NULL DEFAULT 0,
      UNIQUE(attendance_id,project_id))''');
    final now = DateTime.now().toUtc().toIso8601String();
    for (final role in const [
      'Maestro de obra',
      'Albañil',
      'Ayudante',
      'Electricista',
      'Plomero',
      'Pintor',
      'Soldador',
      'Carpintero',
      'Operador de maquinaria',
      'Otros',
    ]) {
      await db.insert('worker_roles', {
        'client_id': 'role-${role.toLowerCase().replaceAll(' ', '-')}',
        'name': role,
        'active': 1,
        'sync_status': 'demo',
        'updated_at': now,
        'is_deleted': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _createCategoriesTable(Database db) => db.execute('''
    CREATE TABLE IF NOT EXISTS categories (
      client_id TEXT PRIMARY KEY,
      remote_id TEXT,
      name TEXT NOT NULL,
      group_name TEXT NOT NULL,
      sync_status TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      UNIQUE(name, group_name)
    )
  ''');

  Future<void> _createProvidersTable(Database db) => db.execute('''
    CREATE TABLE IF NOT EXISTS providers (
      client_id TEXT PRIMARY KEY,
      remote_id TEXT,
      name TEXT NOT NULL UNIQUE,
      contact TEXT NOT NULL DEFAULT '',
      phone TEXT NOT NULL DEFAULT '',
      sync_status TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');

  Future<void> _createSettingsTable(Database db) => db.execute('''
    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'pending'
    )
  ''');

  Future<void> _seedSettings(Database db) => db.insert('settings', {
    'key': 'iva_rate_percent',
    'value': '15.0',
    'updated_at': DateTime.now().toUtc().toIso8601String(),
    'sync_status': 'demo',
  }, conflictAlgorithm: ConflictAlgorithm.ignore);

  Future<void> _seedInitialActualData(Database db) async {
    final imported = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['real_invoice_import_v1'],
      limit: 1,
    );
    if (imported.isNotEmpty) return;

    final now = DateTime.now().toUtc().toIso8601String();
    final expenseDate = DateTime(2026, 8, 15).toUtc().toIso8601String();
    final batch = db.batch();
    const demoExpenses = [
      'demo-cemento',
      'demo-albaniles',
      'demo-transporte',
      'demo-hierro',
      'demo-arena',
    ];
    const demoProjects = ['project-ceibos', 'project-sambo', 'project-olon'];
    for (final id in demoExpenses) {
      batch.delete('expenses', where: 'client_id = ?', whereArgs: [id]);
      batch.insert('sync_queue', {
        'entity_type': 'expense',
        'entity_id': id,
        'operation': 'DELETE',
        'payload_json': '{}',
        'created_at': now,
      });
    }
    for (final id in demoProjects) {
      batch.delete('projects', where: 'client_id = ?', whereArgs: [id]);
      batch.insert('sync_queue', {
        'entity_type': 'project',
        'entity_id': id,
        'operation': 'DELETE',
        'payload_json': '{}',
        'created_at': now,
      });
    }

    const project = {
      'client_id': 'project-real-unassigned',
      'name': 'Por asignar',
      'location': 'Pendiente de definir',
      'budget_cents': 0,
      'spent_cents': 523484,
      'progress': 0.0,
      'status': 'ACTIVE',
      'sync_status': 'pending',
      'is_deleted': 0,
    };
    final projectPayload = {...project, 'updated_at': now};
    batch.insert(
      'projects',
      projectPayload,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    const provider = {
      'client_id': 'provider-su-ferretero',
      'name': 'Su Ferretero - Construcciones Cranbegal Cía. Ltda.',
      'contact': '',
      'phone': '',
      'sync_status': 'pending',
      'is_deleted': 0,
    };
    final providerPayload = {...provider, 'updated_at': now};
    batch.insert(
      'providers',
      providerPayload,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    const categories = [
      ('cat-real-acero', 'Acero', 'Materiales'),
      ('cat-real-consumibles', 'Consumibles', 'Herramientas'),
      ('cat-real-manuales', 'Manuales', 'Herramientas'),
    ];
    for (final category in categories) {
      final payload = {
        'client_id': category.$1,
        'name': category.$2,
        'group_name': category.$3,
        'sync_status': 'pending',
        'updated_at': now,
        'is_deleted': 0,
      };
      batch.insert(
        'categories',
        payload,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      batch.insert('sync_queue', {
        'entity_type': 'category',
        'entity_id': category.$1,
        'operation': 'CREATE',
        'payload_json': jsonEncode(payload),
        'created_at': now,
      });
    }

    final rows = <Map<String, Object?>>[
      _actualExpense(
        'real-fac1-01',
        '001-020-000380000',
        'Materiales · Acero',
        'Hierro Adelca 10 x 12 mm',
        96,
        674,
        64659,
        500,
        3233,
        67892,
        expenseDate,
        now,
      ),
      _actualExpense(
        'real-fac1-02',
        '001-020-000380000',
        'Materiales · Acero',
        'Hierro Adelca 12 x 12 mm',
        207,
        970,
        200811,
        500,
        10041,
        210852,
        expenseDate,
        now,
      ),
      _actualExpense(
        'real-fac1-03',
        '001-020-000380000',
        'Materiales · Acero',
        'Hierro Adelca 14 x 12 m',
        147,
        1320,
        194005,
        1500,
        29101,
        223106,
        expenseDate,
        now,
      ),
      _actualExpense(
        'real-fac1-04',
        '001-020-000380000',
        'Materiales · Acero',
        'Rollo de alambre #18 galvanizado',
        5,
        2881,
        14407,
        1500,
        2161,
        16568,
        expenseDate,
        now,
      ),
      _actualExpense(
        'real-fac1-05',
        '001-020-000380000',
        'Herramientas · Consumibles',
        'Disco de corte para hierro Norton',
        10,
        219,
        2186,
        1500,
        327,
        2513,
        expenseDate,
        now,
      ),
      _actualExpense(
        'real-fac2-01',
        '001-020-000380009',
        'Herramientas · Manuales',
        'Martillo Truper 16 oz',
        1,
        1000,
        1000,
        1500,
        150,
        1150,
        expenseDate,
        now,
      ),
      _actualExpense(
        'real-fac2-02',
        '001-020-000380009',
        'Herramientas · Manuales',
        'Alicate Stanley original',
        1,
        762,
        762,
        1500,
        115,
        877,
        expenseDate,
        now,
      ),
      _actualExpense(
        'real-fac2-03',
        '001-020-000380009',
        'Herramientas · Manuales',
        'Flexómetro Truper 3 m',
        1,
        458,
        458,
        1500,
        68,
        526,
        expenseDate,
        now,
      ),
    ];
    for (final row in rows) {
      batch.insert(
        'expenses',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      batch.insert('sync_queue', {
        'entity_type': 'expense',
        'entity_id': row['client_id'],
        'operation': 'CREATE',
        'payload_json': jsonEncode(row),
        'created_at': now,
      });
    }
    for (final entry in [
      ('project', 'project-real-unassigned', projectPayload),
      ('provider', 'provider-su-ferretero', providerPayload),
    ]) {
      batch.insert('sync_queue', {
        'entity_type': entry.$1,
        'entity_id': entry.$2,
        'operation': 'CREATE',
        'payload_json': jsonEncode(entry.$3),
        'created_at': now,
      });
    }
    batch.insert('settings', {
      'key': 'real_invoice_import_v1',
      'value': '2026-08-15',
      'updated_at': now,
      'sync_status': 'local',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await batch.commit(noResult: true);
  }

  Map<String, Object?> _actualExpense(
    String id,
    String invoiceNumber,
    String category,
    String description,
    double quantity,
    int unitPriceCents,
    int subtotalCents,
    int taxRateBps,
    int taxCents,
    int totalCents,
    String expenseDate,
    String now,
  ) => {
    'client_id': id,
    'remote_id': null,
    'project_name': 'Por asignar',
    'category': category,
    'description': description,
    'provider': 'Su Ferretero - Construcciones Cranbegal Cía. Ltda.',
    'invoice_number': invoiceNumber,
    'quantity': quantity,
    'unit_price_cents': unitPriceCents,
    'subtotal_cents': subtotalCents,
    'tax_rate_bps': taxRateBps,
    'tax_cents': taxCents,
    'total_cents': totalCents,
    'expense_date': expenseDate,
    'created_at': expenseDate,
    'updated_at': now,
    'sync_status': 'pending',
    'is_deleted': 0,
  };

  Future<void> _seedCategories(Database db) async {
    final now = DateTime.now().toUtc().toIso8601String();
    const categories = [
      ('cat-cemento', 'Cemento', 'Materiales'),
      ('cat-hierro', 'Hierro', 'Materiales'),
      ('cat-arena', 'Arena', 'Materiales'),
      ('cat-electricos', 'Material eléctrico', 'Materiales'),
      ('cat-albanil', 'Albañil', 'Mano de obra'),
      ('cat-electricista', 'Electricista', 'Mano de obra'),
      ('cat-plomero', 'Plomero', 'Mano de obra'),
      ('cat-transporte', 'Transporte', 'Otros'),
      ('cat-permisos', 'Permisos', 'Otros'),
      ('cat-imprevistos', 'Imprevistos', 'Otros'),
    ];
    final batch = db.batch();
    for (final category in categories) {
      batch.insert('categories', {
        'client_id': category.$1,
        'name': category.$2,
        'group_name': category.$3,
        'sync_status': 'demo',
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<List<LocalExpense>> getExpenses() async {
    final db = await database;
    final rows = await db.query(
      'expenses',
      where: 'is_deleted = 0',
      orderBy: 'expense_date DESC, created_at DESC',
    );
    return rows.map(LocalExpense.fromMap).toList(growable: false);
  }

  Future<List<LocalProject>> getProjects() async {
    final db = await database;
    final rows = await db.query(
      'projects',
      where: 'is_deleted = 0',
      orderBy: 'updated_at DESC',
    );
    return rows.map(LocalProject.fromMap).toList(growable: false);
  }

  Future<List<LocalCategory>> getCategories() async {
    final db = await database;
    final rows = await db.query(
      'categories',
      where: 'is_deleted = 0',
      orderBy: 'group_name, name',
    );
    return rows.map(LocalCategory.fromMap).toList(growable: false);
  }

  Future<List<LocalProvider>> getProviders() async {
    final db = await database;
    final rows = await db.query(
      'providers',
      where: 'is_deleted = 0',
      orderBy: 'name',
    );
    return rows.map(LocalProvider.fromMap).toList(growable: false);
  }

  Future<DateTime?> getCategoriesFetchedAt() async {
    final db = await database;
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['categories_fetched_at'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['value']! as String)?.toLocal();
  }

  Future<void> setCategoriesFetchedAt(DateTime value) async {
    final db = await database;
    await db.insert('settings', {
      'key': 'categories_fetched_at',
      'value': value.toUtc().toIso8601String(),
      'updated_at': value.toUtc().toIso8601String(),
      'sync_status': 'local',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<double> getVatRatePercent() async {
    final db = await database;
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['iva_rate_percent'],
      limit: 1,
    );
    if (rows.isEmpty) return 15;
    return double.tryParse(rows.first['value']! as String) ?? 15;
  }

  Future<void> setVatRatePercent(double rate) async {
    final db = await database;
    final now = DateTime.now();
    final payload = <String, Object?>{
      'key': 'iva_rate_percent',
      'value': rate.toStringAsFixed(2),
      'updated_at': now.toUtc().toIso8601String(),
      'sync_status': 'pending',
    };
    await db.transaction((txn) async {
      await txn.insert(
        'settings',
        payload,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _enqueue(txn, 'setting', 'iva_rate_percent', 'UPDATE', payload);
    });
  }

  Future<void> insertProject(LocalProject project) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('projects', project.toMap());
      await _enqueue(
        txn,
        'project',
        project.clientId,
        'CREATE',
        project.toMap(),
      );
    });
  }

  Future<void> updateProject(
    LocalProject project, {
    required String previousName,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'projects',
        project.toMap(),
        where: 'client_id = ?',
        whereArgs: [project.clientId],
      );
      if (previousName != project.name) {
        await txn.update(
          'expenses',
          {
            'project_name': project.name,
            'updated_at': project.updatedAt.toUtc().toIso8601String(),
            'sync_status': 'pending',
          },
          where: 'project_name = ? AND is_deleted = 0',
          whereArgs: [previousName],
        );
      }
      await _enqueue(
        txn,
        'project',
        project.clientId,
        'UPDATE',
        project.toMap(),
      );
    });
  }

  Future<bool> softDeleteProject(LocalProject project) async {
    final db = await database;
    final deletedAt = DateTime.now();
    return db.transaction((txn) async {
      final result = await txn.rawQuery(
        'SELECT COUNT(*) AS total FROM expenses WHERE project_name = ? AND is_deleted = 0',
        [project.name],
      );
      if ((Sqflite.firstIntValue(result) ?? 0) > 0) return false;

      final payload = <String, Object?>{
        ...project.toMap(),
        'is_deleted': 1,
        'sync_status': 'pending',
        'updated_at': deletedAt.toUtc().toIso8601String(),
      };
      await txn.update(
        'projects',
        payload,
        where: 'client_id = ? AND is_deleted = 0',
        whereArgs: [project.clientId],
      );
      await _enqueue(txn, 'project', project.clientId, 'DELETE', payload);
      return true;
    });
  }

  Future<void> insertCategory(LocalCategory category) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('categories', category.toMap());
      await _enqueue(
        txn,
        'category',
        category.clientId,
        'CREATE',
        category.toMap(),
      );
    });
  }

  Future<void> updateCategory(LocalCategory category) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'categories',
        category.toMap(),
        where: 'client_id = ?',
        whereArgs: [category.clientId],
      );
      await _enqueue(
        txn,
        'category',
        category.clientId,
        'UPDATE',
        category.toMap(),
      );
    });
  }

  Future<void> softDeleteCategory(LocalCategory category) async {
    final db = await database;
    final updatedAt = DateTime.now();
    await db.transaction((txn) async {
      final payload = <String, Object?>{
        ...category.toMap(),
        'is_deleted': 1,
        'sync_status': 'pending',
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
      await txn.update(
        'categories',
        payload,
        where: 'client_id = ?',
        whereArgs: [category.clientId],
      );
      await _enqueue(txn, 'category', category.clientId, 'DELETE', payload);
    });
  }

  Future<void> insertProvider(LocalProvider provider) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('providers', provider.toMap());
      await _enqueue(
        txn,
        'provider',
        provider.clientId,
        'CREATE',
        provider.toMap(),
      );
    });
  }

  Future<void> updateProvider(LocalProvider provider) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'providers',
        provider.toMap(),
        where: 'client_id = ?',
        whereArgs: [provider.clientId],
      );
      await _enqueue(
        txn,
        'provider',
        provider.clientId,
        'UPDATE',
        provider.toMap(),
      );
    });
  }

  Future<void> softDeleteProvider(LocalProvider provider) async {
    final db = await database;
    final updatedAt = DateTime.now();
    await db.transaction((txn) async {
      final payload = <String, Object?>{
        ...provider.toMap(),
        'is_deleted': 1,
        'sync_status': 'pending',
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
      await txn.update(
        'providers',
        payload,
        where: 'client_id = ?',
        whereArgs: [provider.clientId],
      );
      await _enqueue(txn, 'provider', provider.clientId, 'DELETE', payload);
    });
  }

  Future<void> insertExpense(LocalExpense expense) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('expenses', expense.toMap());
      await txn.rawUpdate(
        'UPDATE projects SET spent_cents = spent_cents + ?, updated_at = ? WHERE name = ? AND is_deleted = 0',
        [
          expense.totalCents,
          expense.updatedAt.toUtc().toIso8601String(),
          expense.projectName,
        ],
      );
      await _enqueue(
        txn,
        'expense',
        expense.clientId,
        'CREATE',
        expense.toMap(),
      );
    });
  }

  Future<void> updateExpense(
    LocalExpense expense, {
    required LocalExpense previous,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'expenses',
        expense.toMap(),
        where: 'client_id = ?',
        whereArgs: [expense.clientId],
      );
      if (previous.projectName == expense.projectName) {
        final difference = expense.totalCents - previous.totalCents;
        await _adjustProjectSpent(
          txn,
          expense.projectName,
          difference,
          expense.updatedAt,
        );
      } else {
        await _adjustProjectSpent(
          txn,
          previous.projectName,
          -previous.totalCents,
          expense.updatedAt,
        );
        await _adjustProjectSpent(
          txn,
          expense.projectName,
          expense.totalCents,
          expense.updatedAt,
        );
      }
      await _enqueue(
        txn,
        'expense',
        expense.clientId,
        'UPDATE',
        expense.toMap(),
      );
    });
  }

  Future<void> softDeleteExpense(LocalExpense expense) async {
    final db = await database;
    final deletedAt = DateTime.now();
    await db.transaction((txn) async {
      final payload = <String, Object?>{
        ...expense.toMap(),
        'is_deleted': 1,
        'sync_status': 'pending',
        'updated_at': deletedAt.toUtc().toIso8601String(),
      };
      await txn.update(
        'expenses',
        payload,
        where: 'client_id = ?',
        whereArgs: [expense.clientId],
      );
      await _adjustProjectSpent(
        txn,
        expense.projectName,
        -expense.totalCents,
        deletedAt,
      );
      await _enqueue(txn, 'expense', expense.clientId, 'DELETE', payload);
    });
  }

  Future<List<LocalWorker>> getWorkers() async {
    final db = await database;
    return (await db.query(
      'workers',
      where: 'is_deleted = 0',
      orderBy: 'full_name',
    )).map(LocalWorker.fromMap).toList(growable: false);
  }

  Future<List<LocalWorkerRole>> getWorkerRoles() async {
    final db = await database;
    return (await db.query(
      'worker_roles',
      where: 'is_deleted = 0 AND active = 1',
      orderBy: 'name',
    )).map(LocalWorkerRole.fromMap).toList(growable: false);
  }

  Future<void> saveWorkerRole(LocalWorkerRole role) =>
      _saveLaborRow('worker_roles', 'worker_role', role.clientId, role.toMap());

  Future<List<LocalAttendance>> getWorkerAttendance() async {
    final db = await database;
    return (await db.query(
      'worker_attendance',
      where: 'is_deleted = 0',
      orderBy: 'attendance_date DESC',
    )).map(LocalAttendance.fromMap).toList(growable: false);
  }

  Future<List<LocalAdvance>> getWorkerAdvances() async {
    final db = await database;
    return (await db.query(
      'worker_advances',
      where: 'is_deleted = 0',
      orderBy: 'advance_date DESC',
    )).map(LocalAdvance.fromMap).toList(growable: false);
  }

  Future<List<LocalWorkerPayment>> getWorkerPayments() async {
    final db = await database;
    return (await db.query(
      'worker_payments',
      where: 'is_deleted = 0',
      orderBy: 'payment_date DESC',
    )).map(LocalWorkerPayment.fromMap).toList(growable: false);
  }

  Future<void> saveWorker(LocalWorker worker) async {
    final db = await database;
    await db.transaction((txn) async {
      final old = await txn.query(
        'workers',
        where: 'client_id = ?',
        whereArgs: [worker.clientId],
        limit: 1,
      );
      await txn.insert(
        'workers',
        worker.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (old.isEmpty ||
          (old.first['default_rate_cents'] as num).toInt() !=
              worker.defaultRateCents) {
        final today = worker.updatedAt.toIso8601String().substring(0, 10);
        await txn.update(
          'worker_rates',
          {
            'valid_to': today,
            'updated_at': worker.updatedAt.toUtc().toIso8601String(),
            'sync_status': 'pending',
          },
          where: "worker_id = ? AND (valid_to IS NULL OR valid_to = '')",
          whereArgs: [worker.clientId],
        );
        final rateId =
            'rate-${worker.clientId}-${worker.updatedAt.microsecondsSinceEpoch}';
        final payload = {
          'client_id': rateId,
          'worker_id': worker.clientId,
          'project_id': '',
          'daily_rate_cents': worker.defaultRateCents,
          'valid_from': today,
          'valid_to': null,
          'sync_status': 'pending',
          'updated_at': worker.updatedAt.toUtc().toIso8601String(),
          'is_deleted': 0,
        };
        await txn.insert('worker_rates', payload);
        await _enqueue(txn, 'worker_rate', rateId, 'CREATE', payload);
      }
      await _enqueue(
        txn,
        'worker',
        worker.clientId,
        old.isEmpty ? 'CREATE' : 'UPDATE',
        worker.toMap(),
      );
    });
  }

  Future<void> saveAttendance(LocalAttendance attendance) async {
    final db = await database;
    await db.transaction((txn) async {
      final allocationRows = await txn.rawQuery(
        'SELECT COALESCE(SUM(allocation_bps),0) AS total FROM worker_attendance WHERE worker_id = ? AND attendance_date = ? AND project_id != ? AND is_deleted = 0',
        [
          attendance.workerId,
          _dateOnlyValue(attendance.date),
          attendance.projectId,
        ],
      );
      final allocated = Sqflite.firstIntValue(allocationRows) ?? 0;
      if (allocated + attendance.allocationBps > 10000) {
        throw StateError(
          'La jornada del trabajador ya está distribuida completamente.',
        );
      }
      final existing = await txn.query(
        'worker_attendance',
        where:
            'worker_id = ? AND project_id = ? AND attendance_date = ? AND is_deleted = 0',
        whereArgs: [
          attendance.workerId,
          attendance.projectId,
          _dateOnlyValue(attendance.date),
        ],
        limit: 1,
      );
      final id = existing.isEmpty
          ? attendance.clientId
          : '${existing.first['client_id']}';
      if (existing.isNotEmpty) {
        final auditId =
            'audit-$id-${attendance.updatedAt.microsecondsSinceEpoch}';
        final audit = <String, Object?>{
          'client_id': auditId,
          'attendance_id': id,
          'snapshot_json': jsonEncode(existing.first),
          'changed_at': attendance.updatedAt.toUtc().toIso8601String(),
          'sync_status': 'pending',
        };
        await txn.insert('worker_attendance_audit', audit);
        await _enqueue(
          txn,
          'worker_attendance_audit',
          auditId,
          'CREATE',
          audit,
        );
      }
      final payload = {
        ...attendance.toMap(),
        'client_id': id,
        'revision': existing.isEmpty
            ? 1
            : ((existing.first['revision'] as num).toInt() + 1),
      };
      await txn.insert(
        'worker_attendance',
        payload,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _enqueue(
        txn,
        'worker_attendance',
        id,
        existing.isEmpty ? 'CREATE' : 'UPDATE',
        payload,
      );
    });
  }

  Future<void> saveAdvance(LocalAdvance advance) => _saveLaborRow(
    'worker_advances',
    'worker_advance',
    advance.clientId,
    advance.toMap(),
  );
  Future<void> saveWorkerPayment(LocalWorkerPayment payment) => _saveLaborRow(
    'worker_payments',
    'worker_payment',
    payment.clientId,
    payment.toMap(),
  );

  Future<void> _saveLaborRow(
    String table,
    String type,
    String id,
    Map<String, Object?> payload,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      final exists =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM $table WHERE client_id = ?',
              [id],
            ),
          )! >
          0;
      await txn.insert(
        table,
        payload,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _enqueue(txn, type, id, exists ? 'UPDATE' : 'CREATE', payload);
    });
  }

  String _dateOnlyValue(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _adjustProjectSpent(
    DatabaseExecutor executor,
    String projectName,
    int difference,
    DateTime updatedAt,
  ) => executor.rawUpdate(
    'UPDATE projects SET spent_cents = MAX(0, spent_cents + ?), updated_at = ?, sync_status = ? WHERE name = ? AND is_deleted = 0',
    [difference, updatedAt.toUtc().toIso8601String(), 'pending', projectName],
  );

  Future<void> _enqueue(
    DatabaseExecutor executor,
    String entityType,
    String entityId,
    String operation,
    Map<String, Object?> payload,
  ) => executor.insert('sync_queue', {
    'entity_type': entityType,
    'entity_id': entityId,
    'operation': operation,
    'payload_json': jsonEncode(payload),
    'created_at': DateTime.now().toUtc().toIso8601String(),
  });

  Future<int> pendingSyncCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM sync_queue',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<SyncQueueItem>> getSyncQueue() async {
    final db = await database;
    final rows = await db.query('sync_queue', orderBy: 'id ASC');
    return rows.map(SyncQueueItem.fromMap).toList(growable: false);
  }

  Future<void> completeSyncItem(SyncQueueItem item) async {
    final db = await database;
    await db.transaction((txn) async {
      final table = switch (item.entityType) {
        'project' => 'projects',
        'expense' => 'expenses',
        'category' => 'categories',
        'provider' => 'providers',
        'worker' => 'workers',
        'worker_role' => 'worker_roles',
        'worker_rate' => 'worker_rates',
        'worker_attendance' => 'worker_attendance',
        'worker_attendance_audit' => 'worker_attendance_audit',
        'worker_advance' => 'worker_advances',
        'worker_payment' => 'worker_payments',
        _ => null,
      };
      if (table != null) {
        if (item.operation == 'DELETE') {
          await txn.delete(
            table,
            where: 'client_id = ?',
            whereArgs: [item.entityId],
          );
        } else {
          await txn.update(
            table,
            {'sync_status': 'synced', 'remote_id': item.entityId},
            where: 'client_id = ?',
            whereArgs: [item.entityId],
          );
        }
      } else if (item.entityType == 'setting') {
        await txn.update(
          'settings',
          {'sync_status': 'synced'},
          where: 'key = ?',
          whereArgs: [item.entityId],
        );
      }
      await txn.delete('sync_queue', where: 'id = ?', whereArgs: [item.id]);
    });
  }

  Future<void> markAllSynced() async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in [
        'projects',
        'expenses',
        'categories',
        'providers',
        'workers',
        'worker_roles',
        'worker_assignments',
        'worker_rates',
        'worker_attendance',
        'worker_attendance_audit',
        'worker_advances',
        'payroll_periods',
        'payroll_items',
        'worker_payments',
        'labor_cost_allocations',
      ]) {
        await txn.update(table, {'sync_status': 'synced'});
      }
      await txn.update('settings', {'sync_status': 'synced'});
      await txn.delete('sync_queue');
    });
  }

  Future<void> replaceDemoWithRemote({
    required List<LocalProject> projects,
    required List<LocalExpense> expenses,
    required List<LocalCategory> categories,
    required List<LocalProvider> providers,
    required double vatRatePercent,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('expenses', where: "sync_status IN ('demo', 'synced')");
      await txn.delete('projects', where: "sync_status IN ('demo', 'synced')");
      await txn.delete(
        'categories',
        where: "sync_status IN ('demo', 'synced')",
      );
      await txn.delete('providers', where: "sync_status IN ('demo', 'synced')");

      for (final project in projects) {
        await txn.insert(
          'projects',
          project.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final category in categories) {
        await txn.insert(
          'categories',
          category.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final expense in expenses) {
        await txn.insert(
          'expenses',
          expense.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final provider in providers) {
        await txn.insert(
          'providers',
          provider.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await txn.rawUpdate('UPDATE projects SET spent_cents = 0');
      await txn.rawUpdate('''
        UPDATE projects
        SET spent_cents = COALESCE((
          SELECT SUM(expenses.total_cents)
          FROM expenses
          WHERE expenses.project_name = projects.name
            AND expenses.is_deleted = 0
        ), 0)
      ''');
      await txn.insert('settings', {
        'key': 'iva_rate_percent',
        'value': vatRatePercent.toStringAsFixed(2),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'sync_status': 'synced',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> replaceLaborRemote({
    required List<LocalWorkerRole> roles,
    required List<LocalWorker> workers,
    required List<LocalAttendance> attendance,
    required List<LocalAdvance> advances,
    required List<LocalWorkerPayment> payments,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final pair in [
        ('worker_roles', roles.map((e) => e.toMap())),
        ('workers', workers.map((e) => e.toMap())),
        ('worker_attendance', attendance.map((e) => e.toMap())),
        ('worker_advances', advances.map((e) => e.toMap())),
        ('worker_payments', payments.map((e) => e.toMap())),
      ]) {
        final table = pair.$1;
        await txn.delete(table, where: "sync_status = 'synced'");
        for (final row in pair.$2) {
          await txn.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }
}

class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
  });

  final int id;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, dynamic> payload;

  factory SyncQueueItem.fromMap(Map<String, Object?> map) => SyncQueueItem(
    id: map['id']! as int,
    entityType: map['entity_type']! as String,
    entityId: map['entity_id']! as String,
    operation: map['operation']! as String,
    payload: jsonDecode(map['payload_json']! as String) as Map<String, dynamic>,
  );
}
