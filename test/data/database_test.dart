import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fairshare/core/constants/app_constants.dart';
import 'package:fairshare/data/database/database_helper.dart';
import 'package:fairshare/data/models/expense_split_model.dart';
import 'package:fairshare/data/repositories/event_repository.dart';
import 'package:fairshare/data/repositories/expense_repository.dart';
import 'package:fairshare/data/repositories/people_repository.dart';
import 'package:fairshare/data/repositories/settlement_repository.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late PeopleRepository peopleRepo;
  late EventRepository eventRepo;
  late ExpenseRepository expenseRepo;
  late SettlementRepository settlementRepo;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await DatabaseHelper.createSchema(db);
    DatabaseHelper.setDatabaseForTesting(db);

    peopleRepo = PeopleRepository();
    eventRepo = EventRepository();
    expenseRepo = ExpenseRepository();
    settlementRepo = SettlementRepository();
  });

  tearDown(() async {
    await db.close();
  });

  test('full workflow: people, event, expense, and settlement persistence', () async {
    // 1. Create People
    final p1 = await peopleRepo.createOrFindPerson(
      name: 'Alice',
      phoneNumber: '9876543210',
    );
    final p2 = await peopleRepo.createOrFindPerson(
      name: 'Bob',
      phoneNumber: '9876543211',
    );

    expect(p1.name, 'Alice');
    expect(p2.name, 'Bob');

    // 2. Create Event with members
    final event = await eventRepo.createEvent(
      title: 'Goa Vacation',
      eventType: EventCategories.trip,
      currency: '₹',
      memberPersonIds: [p1.id, p2.id],
    );

    expect(event.title, 'Goa Vacation');
    expect(event.members.length, 2);

    // 3. Add Expense: Alice pays 1000, split 500 each
    final expense = await expenseRepo.createExpense(
      eventId: event.id,
      payerId: p1.id,
      title: 'Beach Shack Lunch',
      amount: 1000.0,
      category: ExpenseCategories.food,
      splitType: SplitType.equal,
      date: DateTime.now(),
      receiptPath: '/storage/emulated/0/DCIM/bill_receipt_123.jpg',
      splits: [
        ExpenseSplitModel(
          id: '',
          expenseId: '',
          personId: p1.id,
          allocatedAmount: 500.0,
          rawValue: 1.0,
        ),
        ExpenseSplitModel(
          id: '',
          expenseId: '',
          personId: p2.id,
          allocatedAmount: 500.0,
          rawValue: 1.0,
        ),
      ],
    );

    expect(expense.amount, 1000.0);
    expect(expense.splits.length, 2);
    expect(expense.receiptPath, '/storage/emulated/0/DCIM/bill_receipt_123.jpg');

    final fetchedExpenses = await expenseRepo.getExpensesForEvent(event.id);
    expect(fetchedExpenses.first.receiptPath, '/storage/emulated/0/DCIM/bill_receipt_123.jpg');

    // Verify Event Summary
    final summary = await eventRepo.getEventSummary(event.id);
    expect(summary.totalSpend, 1000.0);
    expect(summary.expenseCount, 1);
    expect(summary.memberCount, 2);

    // 4. Record Settlement: Bob pays Alice 500
    final settlement = await settlementRepo.recordSettlement(
      eventId: event.id,
      payerId: p2.id,
      payeeId: p1.id,
      amount: 500.0,
      settledAt: DateTime.now(),
      note: 'GPay transfer',
    );

    expect(settlement.amount, 500.0);
    final settlements = await settlementRepo.getSettlementsForEvent(event.id);
    expect(settlements.length, 1);
    expect(settlements.first.note, 'GPay transfer');
  });

  test('full backup export and restore round-trip with foreign keys', () async {
    // Enable foreign keys explicitly
    await db.execute('PRAGMA foreign_keys = ON');

    // 1. Seed initial data
    final self = await peopleRepo.getSelfPerson();
    expect(self, isNotNull);

    final friend = await peopleRepo.createOrFindPerson(
      name: 'Bob Test',
      phoneNumber: '9988776655',
    );

    final event = await eventRepo.createEvent(
      title: 'Road Trip 2026',
      eventType: EventCategories.trip,
      currency: '₹',
      memberPersonIds: [self!.id, friend.id],
    );

    await expenseRepo.createExpense(
      eventId: event.id,
      payerId: self.id,
      title: 'Fuel',
      amount: 2000.0,
      category: ExpenseCategories.travel,
      splitType: SplitType.equal,
      date: DateTime.now(),
      splits: [
        ExpenseSplitModel(
          id: '',
          expenseId: '',
          personId: self.id,
          allocatedAmount: 1000.0,
          rawValue: 1.0,
        ),
        ExpenseSplitModel(
          id: '',
          expenseId: '',
          personId: friend.id,
          allocatedAmount: 1000.0,
          rawValue: 1.0,
        ),
      ],
    );

    // 2. Export full backup
    final backupPayload = await DatabaseHelper.instance.exportFullBackup();
    expect(backupPayload['tables'], isNotNull);
    final tables = backupPayload['tables'] as Map<String, dynamic>;
    expect((tables['events'] as List).length, 1);
    expect((tables['expenses'] as List).length, 1);
    expect((tables['people'] as List).length, greaterThanOrEqualTo(2));

    // 3. Simulate app reinstall / fresh database
    await databaseFactory.deleteDatabase('in_memory_db2.db');
    final db2 = await databaseFactory.openDatabase('in_memory_db2.db');
    await DatabaseHelper.createSchema(db2);
    await db2.execute('PRAGMA foreign_keys = ON');
    DatabaseHelper.setDatabaseForTesting(db2);

    // Fresh install creates a dummy 'You'
    final freshPeopleRepo = PeopleRepository(databaseHelper: DatabaseHelper.instance);
    final dummySelf = await freshPeopleRepo.getSelfPerson();
    expect(dummySelf, isNotNull);

    // 4. Restore the backup payload into db2
    final stats = await DatabaseHelper.instance.restoreFullBackup(backupPayload);
    expect(stats['events'], 1);
    expect(stats['expenses'], 1);

    // 5. Verify restored data in repositories
    final freshEventRepo = EventRepository(databaseHelper: DatabaseHelper.instance);
    final freshExpenseRepo = ExpenseRepository(databaseHelper: DatabaseHelper.instance);

    final restoredEvents = await freshEventRepo.getAllEvents();
    expect(restoredEvents.length, 1);
    expect(restoredEvents.first.title, 'Road Trip 2026');

    final restoredExpenses = await freshExpenseRepo.getExpensesForEvent(restoredEvents.first.id);
    expect(restoredExpenses.length, 1);
    expect(restoredExpenses.first.title, 'Fuel');
    expect(restoredExpenses.first.amount, 2000.0);

    // Verify self person was properly reconciled to the original user
    final resolvedSelf = await freshPeopleRepo.getSelfPerson();
    expect(resolvedSelf, isNotNull);
    expect(resolvedSelf!.id, self.id);

    await db2.close();
  });
}
