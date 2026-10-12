import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/expense_model.dart';
import '../models/expense_split_model.dart';

class ExpenseRepository {
  final DatabaseHelper _databaseHelper;
  final Uuid _uuid = const Uuid();

  ExpenseRepository({DatabaseHelper? databaseHelper})
      : _databaseHelper = databaseHelper ?? DatabaseHelper.instance;

  Future<List<ExpenseModel>> getExpensesForEvent(
    String eventId, {
    bool onlyApproved = false,
  }) async {
    final db = await _databaseHelper.database;
    final whereClause = onlyApproved
        ? "event_id = ? AND (approval_status = 'approved' OR approval_status IS NULL)"
        : 'event_id = ?';

    final expenseMaps = await db.query(
      'expenses',
      where: whereClause,
      whereArgs: [eventId],
      orderBy: 'date DESC, rowid DESC',
    );
    if (expenseMaps.isEmpty) return [];

    final expenseIds = expenseMaps.map((e) => e['id'] as String).toList();
    final placeholders = List.filled(expenseIds.length, '?').join(',');
    final splitMaps = await db.rawQuery(
      'SELECT * FROM expense_splits WHERE expense_id IN ($placeholders)',
      expenseIds,
    );

    final Map<String, List<ExpenseSplitModel>> splitsByExpense = {};
    for (final sm in splitMaps) {
      final expId = sm['expense_id'] as String;
      splitsByExpense.putIfAbsent(expId, () => []).add(ExpenseSplitModel.fromMap(sm));
    }

    return expenseMaps.map((map) {
      final id = map['id'] as String;
      return ExpenseModel.fromMap(map, splits: splitsByExpense[id] ?? []);
    }).toList();
  }

  Future<List<ExpenseModel>> getPendingExpensesForEvent(String eventId) async {
    final db = await _databaseHelper.database;
    final expenseMaps = await db.query(
      'expenses',
      where: "event_id = ? AND approval_status = 'pending'",
      whereArgs: [eventId],
      orderBy: 'date DESC, rowid DESC',
    );
    if (expenseMaps.isEmpty) return [];

    final expenseIds = expenseMaps.map((e) => e['id'] as String).toList();
    final placeholders = List.filled(expenseIds.length, '?').join(',');
    final splitMaps = await db.rawQuery(
      'SELECT * FROM expense_splits WHERE expense_id IN ($placeholders)',
      expenseIds,
    );

    final Map<String, List<ExpenseSplitModel>> splitsByExpense = {};
    for (final sm in splitMaps) {
      final expId = sm['expense_id'] as String;
      splitsByExpense.putIfAbsent(expId, () => []).add(ExpenseSplitModel.fromMap(sm));
    }

    return expenseMaps.map((map) {
      final id = map['id'] as String;
      return ExpenseModel.fromMap(map, splits: splitsByExpense[id] ?? []);
    }).toList();
  }

  Future<ExpenseModel> createExpense({
    required String eventId,
    required String payerId,
    required String title,
    required double amount,
    required String category,
    required dynamic splitType,
    required DateTime date,
    String? location,
    double? latitude,
    double? longitude,
    String? receiptPath,
    required List<ExpenseSplitModel> splits,
    ExpenseApprovalStatus approvalStatus = ExpenseApprovalStatus.approved,
    String? submittedByPersonId,
    String? submittedByName,
    bool isCommitteeSpend = false,
  }) async {
    final db = await _databaseHelper.database;
    final expenseId = _uuid.v4();

    final expense = ExpenseModel(
      id: expenseId,
      eventId: eventId,
      payerId: payerId,
      title: title,
      amount: amount,
      category: category,
      splitType: splitType,
      date: date,
      location: location,
      latitude: latitude,
      longitude: longitude,
      receiptPath: receiptPath,
      approvalStatus: approvalStatus,
      submittedByPersonId: submittedByPersonId,
      submittedByName: submittedByName,
      approvedAt: approvalStatus == ExpenseApprovalStatus.approved ? DateTime.now() : null,
      isCommitteeSpend: isCommitteeSpend,
    );

    await db.transaction((txn) async {
      await txn.insert('expenses', expense.toMap());

      for (final split in splits) {
        final splitToInsert = split.copyWith(
          id: split.id.isEmpty ? _uuid.v4() : split.id,
          expenseId: expenseId,
        );
        await txn.insert('expense_splits', splitToInsert.toMap());
      }
    });

    return expense.copyWith(splits: splits);
  }

  Future<void> updateExpense({
    required ExpenseModel expense,
    required List<ExpenseSplitModel> splits,
  }) async {
    final db = await _databaseHelper.database;

    await db.transaction((txn) async {
      await txn.update(
        'expenses',
        expense.toMap(),
        where: 'id = ?',
        whereArgs: [expense.id],
      );

      await txn.delete(
        'expense_splits',
        where: 'expense_id = ?',
        whereArgs: [expense.id],
      );

      for (final split in splits) {
        final splitToInsert = split.copyWith(
          id: split.id.isEmpty ? _uuid.v4() : split.id,
          expenseId: expense.id,
        );
        await txn.insert('expense_splits', splitToInsert.toMap());
      }
    });
  }

  Future<void> approveExpense(String expenseId) async {
    final db = await _databaseHelper.database;
    await db.update(
      'expenses',
      {
        'approval_status': ExpenseApprovalStatus.approved.dbValue,
        'approved_at': DateTime.now().millisecondsSinceEpoch,
        'rejection_reason': null,
      },
      where: 'id = ?',
      whereArgs: [expenseId],
    );
  }

  Future<void> rejectExpense(String expenseId, {String? reason}) async {
    final db = await _databaseHelper.database;
    await db.update(
      'expenses',
      {
        'approval_status': ExpenseApprovalStatus.rejected.dbValue,
        'rejection_reason': reason,
      },
      where: 'id = ?',
      whereArgs: [expenseId],
    );
  }

  Future<void> deleteExpense(String expenseId) async {
    final db = await _databaseHelper.database;
    await db.delete(
      'expenses',
      where: 'id = ?',
      whereArgs: [expenseId],
    );
  }
}
