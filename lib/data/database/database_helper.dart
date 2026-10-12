import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/constants/app_constants.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Allow setting database for testing (e.g. sqflite_common_ffi in memory)
  static void setDatabaseForTesting(Database db) {
    _database = db;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'fairshare.db');

    return await openDatabase(
      path,
      version: 6,
      onCreate: _createDb,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _addColumnIfNotExists(db, 'expenses', 'location', 'TEXT');
          await _addColumnIfNotExists(db, 'expenses', 'latitude', 'REAL');
          await _addColumnIfNotExists(db, 'expenses', 'longitude', 'REAL');
        }
        if (oldVersion < 3) {
          await _createCategoriesTable(db);
          await _seedDefaultCategories(db);
        }
        if (oldVersion < 4) {
          await _addColumnIfNotExists(db, 'expenses', 'receipt_path', 'TEXT');
        }
        if (oldVersion < 5) {
          // people columns
          await _addColumnIfNotExists(db, 'people', 'upi_id', 'TEXT');
          await _addColumnIfNotExists(db, 'people', 'count', 'INTEGER NOT NULL DEFAULT 1');

          // events columns
          await _addColumnIfNotExists(db, 'events', 'status', "TEXT NOT NULL DEFAULT 'active'");
          await _addColumnIfNotExists(db, 'events', 'estimated_budget', 'REAL NOT NULL DEFAULT 0.0');
          await _addColumnIfNotExists(db, 'events', 'installments_count', 'INTEGER NOT NULL DEFAULT 1');
          await _addColumnIfNotExists(db, 'events', 'creator_id', 'TEXT');
          await _addColumnIfNotExists(db, 'events', 'creator_email', 'TEXT');
          await _addColumnIfNotExists(db, 'events', 'drive_file_id', 'TEXT');
          await _addColumnIfNotExists(db, 'events', 'share_code', 'TEXT');
          await _addColumnIfNotExists(db, 'events', 'is_shared', 'INTEGER NOT NULL DEFAULT 0');
          await _addColumnIfNotExists(db, 'events', 'last_synced_at', 'INTEGER');

          // event_participants columns
          await _addColumnIfNotExists(db, 'event_participants', 'count', 'INTEGER NOT NULL DEFAULT 1');

          // expenses columns
          await _addColumnIfNotExists(db, 'expenses', 'approval_status', "TEXT NOT NULL DEFAULT 'approved'");
          await _addColumnIfNotExists(db, 'expenses', 'submitted_by_person_id', 'TEXT');
          await _addColumnIfNotExists(db, 'expenses', 'submitted_by_name', 'TEXT');
          await _addColumnIfNotExists(db, 'expenses', 'rejection_reason', 'TEXT');
          await _addColumnIfNotExists(db, 'expenses', 'approved_at', 'INTEGER');
          await _addColumnIfNotExists(db, 'expenses', 'is_committee_spend', 'INTEGER NOT NULL DEFAULT 0');

          // trip_installments table
          await _createTripInstallmentsTable(db);
        }
        if (oldVersion < 6) {
          await _addColumnIfNotExists(db, 'events', 'last_synced_at', 'INTEGER');
        }
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onOpen: (db) async {
        await _addColumnIfNotExists(db, 'events', 'last_synced_at', 'INTEGER');
      },
    );
  }

  static Future<void> createSchema(Database db) async {
    await _createDb(db, 6);
  }

  static Future<void> _addColumnIfNotExists(
    DatabaseExecutor db,
    String table,
    String column,
    String typeDef,
  ) async {
    try {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      final columnNames = info.map((c) => c['name'] as String).toSet();
      if (!columnNames.contains(column)) {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $typeDef');
      }
    } catch (_) {
      // Column might already exist or table alteration failed safely
    }
  }

  static Future<void> _createTripInstallmentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trip_installments (
        id TEXT PRIMARY KEY,
        event_id TEXT NOT NULL,
        installment_number INTEGER NOT NULL DEFAULT 1,
        person_id TEXT NOT NULL,
        expected_amount REAL NOT NULL DEFAULT 0.0,
        paid_amount REAL NOT NULL DEFAULT 0.0,
        is_paid INTEGER NOT NULL DEFAULT 0,
        paid_at INTEGER,
        notes TEXT,
        FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
        FOREIGN KEY (person_id) REFERENCES people(id) ON DELETE RESTRICT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_installments_event ON trip_installments(event_id)',
    );
  }

  static Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE people (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone_number TEXT NOT NULL,
        contact_id TEXT,
        avatar_color TEXT,
        is_self INTEGER NOT NULL DEFAULT 0,
        upi_id TEXT,
        count INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE events (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        event_type TEXT NOT NULL,
        currency TEXT NOT NULL DEFAULT '₹',
        description TEXT,
        created_at INTEGER NOT NULL,
        is_archived INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'active',
        estimated_budget REAL NOT NULL DEFAULT 0.0,
        installments_count INTEGER NOT NULL DEFAULT 1,
        creator_id TEXT,
        creator_email TEXT,
        drive_file_id TEXT,
        share_code TEXT,
        is_shared INTEGER NOT NULL DEFAULT 0,
        last_synced_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE event_participants (
        event_id TEXT NOT NULL,
        person_id TEXT NOT NULL,
        count INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (event_id, person_id),
        FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
        FOREIGN KEY (person_id) REFERENCES people(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id TEXT PRIMARY KEY,
        event_id TEXT NOT NULL,
        payer_id TEXT NOT NULL,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT NOT NULL,
        split_type TEXT NOT NULL,
        date INTEGER NOT NULL,
        location TEXT,
        latitude REAL,
        longitude REAL,
        receipt_path TEXT,
        approval_status TEXT NOT NULL DEFAULT 'approved',
        submitted_by_person_id TEXT,
        submitted_by_name TEXT,
        rejection_reason TEXT,
        approved_at INTEGER,
        is_committee_spend INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
        FOREIGN KEY (payer_id) REFERENCES people(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE expense_splits (
        id TEXT PRIMARY KEY,
        expense_id TEXT NOT NULL,
        person_id TEXT NOT NULL,
        allocated_amount REAL NOT NULL,
        raw_value REAL NOT NULL,
        FOREIGN KEY (expense_id) REFERENCES expenses(id) ON DELETE CASCADE,
        FOREIGN KEY (person_id) REFERENCES people(id) ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE settlements (
        id TEXT PRIMARY KEY,
        event_id TEXT NOT NULL,
        payer_id TEXT NOT NULL,
        payee_id TEXT NOT NULL,
        amount REAL NOT NULL,
        settled_at INTEGER NOT NULL,
        note TEXT,
        FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
        FOREIGN KEY (payer_id) REFERENCES people(id) ON DELETE RESTRICT,
        FOREIGN KEY (payee_id) REFERENCES people(id) ON DELETE RESTRICT
      )
    ''');

    await _createTripInstallmentsTable(db);

    // Indices for performant querying
    await db.execute('CREATE INDEX idx_expenses_event ON expenses(event_id)');
    await db.execute('CREATE INDEX idx_splits_expense ON expense_splits(expense_id)');
    await db.execute('CREATE INDEX idx_settlements_event ON settlements(event_id)');
    await db.execute('CREATE INDEX idx_participants_event ON event_participants(event_id)');

    await _createCategoriesTable(db);
    await _seedDefaultCategories(db);
  }

  static Future<void> _createCategoriesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        icon_code INTEGER NOT NULL,
        color_value INTEGER,
        is_default INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_categories_type ON categories(type)');
  }

  static Future<void> _seedDefaultCategories(Database db) async {
    final batch = db.batch();

    // Default Expense Categories
    for (final cat in ExpenseCategories.all) {
      final id = 'expense_${cat.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
      batch.insert(
        'categories',
        {
          'id': id,
          'name': cat,
          'type': 'expense',
          'icon_code': ExpenseCategories.getIcon(cat).codePoint,
          'color_value': ExpenseCategories.getColor(cat).toARGB32(),
          'is_default': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    // Default Event Categories
    for (final cat in EventCategories.all) {
      final id = 'event_${cat.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
      batch.insert(
        'categories',
        {
          'id': id,
          'name': cat,
          'type': 'event',
          'icon_code': EventCategories.getIcon(cat).codePoint,
          'color_value': EventCategories.getColor(cat).toARGB32(),
          'is_default': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Query live count of records across all tables.
  Future<Map<String, int>> getDatabaseItemCounts() async {
    final db = await database;
    final peopleCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM people')) ??
        0;
    final eventsCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM events')) ??
        0;
    final expensesCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM expenses')) ??
        0;
    final splitsCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM expense_splits')) ??
        0;
    final settlementsCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM settlements')) ??
        0;
    final categoriesCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM categories')) ??
        0;
    final installmentsCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM trip_installments')) ??
        0;
    final participantsCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM event_participants')) ??
        0;

    return {
      'people': peopleCount,
      'events': eventsCount,
      'expenses': expensesCount,
      'splits': splitsCount,
      'settlements': settlementsCount,
      'categories': categoriesCount,
      'installments': installmentsCount,
      'participants': participantsCount,
    };
  }

  /// Exports all application data into a comprehensive backup payload.
  Future<Map<String, dynamic>> exportFullBackup() async {
    final db = await database;

    final people = await db.query('people');
    final events = await db.query('events');
    final eventParticipants = await db.query('event_participants');
    final expenses = await db.query('expenses');
    final expenseSplits = await db.query('expense_splits');
    final settlements = await db.query('settlements');
    final categories = await db.query('categories');
    final tripInstallments = await db.query('trip_installments');

    final prefs = await SharedPreferences.getInstance();
    final userUpiId = prefs.getString('user_upi_id');
    final userPhone = prefs.getString('auth_phone_number');
    final themeMode = prefs.getString('theme_mode');
    final defaultCurrency = prefs.getString('default_currency');

    return {
      'schema_version': 1,
      'app': 'FairShare',
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'tables': {
        'people': people,
        'events': events,
        'event_participants': eventParticipants,
        'expenses': expenses,
        'expense_splits': expenseSplits,
        'settlements': settlements,
        'categories': categories,
        'trip_installments': tripInstallments,
      },
      'user_preferences': {
        'user_upi_id': ?userUpiId,
        'user_phone_number': ?userPhone,
        'auth_phone_number': ?userPhone,
        'theme_mode': ?themeMode,
        'default_currency': ?defaultCurrency,
      },
      'stats': {
        'people_count': people.length,
        'events_count': events.length,
        'expenses_count': expenses.length,
        'splits_count': expenseSplits.length,
        'settlements_count': settlements.length,
        'categories_count': categories.length,
        'installments_count': tripInstallments.length,
        'participants_count': eventParticipants.length,
      },
    };
  }

  /// Restores all application data from a backup payload atomically.
  Future<Map<String, int>> restoreFullBackup(Map<String, dynamic> backup) async {
    final db = await database;
    final tables = backup['tables'] as Map<String, dynamic>?;
    if (tables == null) {
      throw const FormatException('Invalid backup payload: missing tables section');
    }

    final stats = <String, int>{};

    // Disable foreign key enforcement during full restore so that replacement
    // deletes and updates on parent tables (people, events) do not violate RESTRICT constraints.
    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction((txn) async {
        // 1. Restore categories
        if (tables['categories'] is List) {
          final categories = List<Map<String, dynamic>>.from(tables['categories']);
          for (final row in categories) {
            await txn.insert(
              'categories',
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          stats['categories'] = categories.length;
        }

        // 2. Restore people
        if (tables['people'] is List) {
          final people = List<Map<String, dynamic>>.from(tables['people']);

          // If the incoming backup has an existing self person, clean up any blank/unattached
          // dummy self person that might have been automatically created during fresh app launch.
          final hasBackupSelf = people.any((p) => p['is_self'] == 1 || p['is_self'] == true);
          if (hasBackupSelf) {
            await txn.rawDelete('''
              DELETE FROM people 
              WHERE is_self = 1 
                AND id NOT IN (SELECT payer_id FROM expenses)
                AND id NOT IN (SELECT person_id FROM expense_splits)
                AND id NOT IN (SELECT person_id FROM event_participants)
            ''');
          }

          for (final row in people) {
            await txn.insert(
              'people',
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          stats['people'] = people.length;
        }

        // 3. Restore events
        if (tables['events'] is List) {
          final events = List<Map<String, dynamic>>.from(tables['events']);
          for (final row in events) {
            await txn.insert(
              'events',
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          stats['events'] = events.length;
        }

        // 4. Restore event_participants
        if (tables['event_participants'] is List) {
          final participants =
              List<Map<String, dynamic>>.from(tables['event_participants']);
          for (final row in participants) {
            await txn.insert(
              'event_participants',
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          stats['participants'] = participants.length;
        }

        // 5. Restore expenses
        if (tables['expenses'] is List) {
          final expenses = List<Map<String, dynamic>>.from(tables['expenses']);
          for (final row in expenses) {
            await txn.insert(
              'expenses',
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          stats['expenses'] = expenses.length;
        }

        // 6. Restore expense_splits
        if (tables['expense_splits'] is List) {
          final splits = List<Map<String, dynamic>>.from(tables['expense_splits']);
          for (final row in splits) {
            await txn.insert(
              'expense_splits',
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          stats['splits'] = splits.length;
        }

        // 7. Restore settlements
        if (tables['settlements'] is List) {
          final settlements =
              List<Map<String, dynamic>>.from(tables['settlements']);
          for (final row in settlements) {
            await txn.insert(
              'settlements',
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          stats['settlements'] = settlements.length;
        }

        // 8. Restore trip_installments
        if (tables['trip_installments'] is List) {
          final installments =
              List<Map<String, dynamic>>.from(tables['trip_installments']);
          for (final row in installments) {
            await txn.insert(
              'trip_installments',
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          stats['trip_installments'] = installments.length;
        }
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }

    // Restore user preferences if present
    if (backup['user_preferences'] is Map) {
      try {
        final userPrefs = backup['user_preferences'] as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();
        if (userPrefs['auth_phone_number'] is String &&
            (userPrefs['auth_phone_number'] as String).isNotEmpty) {
          await prefs.setString(
              'auth_phone_number', userPrefs['auth_phone_number'] as String);
        } else if (userPrefs['user_phone_number'] is String &&
            (userPrefs['user_phone_number'] as String).isNotEmpty) {
          await prefs.setString(
              'auth_phone_number', userPrefs['user_phone_number'] as String);
        }
        if (userPrefs['user_upi_id'] is String &&
            (userPrefs['user_upi_id'] as String).isNotEmpty) {
          await prefs.setString(
              'user_upi_id', userPrefs['user_upi_id'] as String);
        }
        if (userPrefs['theme_mode'] is String) {
          await prefs.setString(
              'theme_mode', userPrefs['theme_mode'] as String);
        }
        if (userPrefs['default_currency'] is String) {
          await prefs.setString(
              'default_currency', userPrefs['default_currency'] as String);
        }
      } catch (_) {}
    }

    return stats;
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
