import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/expense_split_model.dart';
import '../../data/models/settlement_model.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/settlement_repository.dart';

class ExpenseProvider extends ChangeNotifier {
  final ExpenseRepository _expenseRepository;
  final SettlementRepository _settlementRepository;

  List<ExpenseModel> _expenses = [];
  List<SettlementModel> _settlements = [];
  bool _isLoading = false;
  String? _errorMessage;

  ExpenseProvider({
    ExpenseRepository? expenseRepository,
    SettlementRepository? settlementRepository,
  })  : _expenseRepository = expenseRepository ?? ExpenseRepository(),
        _settlementRepository = settlementRepository ?? SettlementRepository();

  List<ExpenseModel> get expenses => _expenses;
  List<ExpenseModel> get approvedExpenses =>
      _expenses.where((e) => e.isApproved).toList();
  List<ExpenseModel> get pendingExpenses =>
      _expenses.where((e) => e.isPending).toList();
  List<SettlementModel> get settlements => _settlements;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadForEvent(String eventId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _expenses = await _expenseRepository.getExpensesForEvent(eventId);
      _settlements = await _settlementRepository.getSettlementsForEvent(eventId);
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<ExpenseModel> addExpense({
    required String eventId,
    required String payerId,
    required String title,
    required double amount,
    required String category,
    required SplitType splitType,
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
    final expense = await _expenseRepository.createExpense(
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
      splits: splits,
      approvalStatus: approvalStatus,
      submittedByPersonId: submittedByPersonId,
      submittedByName: submittedByName,
      isCommitteeSpend: isCommitteeSpend,
    );
    await loadForEvent(eventId);
    return expense;
  }

  Future<void> updateExpense({
    required ExpenseModel expense,
    required List<ExpenseSplitModel> splits,
  }) async {
    await _expenseRepository.updateExpense(
      expense: expense,
      splits: splits,
    );
    await loadForEvent(expense.eventId);
  }

  Future<void> approveExpense(String expenseId, String eventId) async {
    await _expenseRepository.approveExpense(expenseId);
    await loadForEvent(eventId);
  }

  Future<void> rejectExpense(String expenseId, String eventId, {String? reason}) async {
    await _expenseRepository.rejectExpense(expenseId, reason: reason);
    await loadForEvent(eventId);
  }

  Future<void> deleteExpense(String expenseId, String eventId) async {
    await _expenseRepository.deleteExpense(expenseId);
    await loadForEvent(eventId);
  }

  Future<SettlementModel> recordSettlement({
    required String eventId,
    required String payerId,
    required String payeeId,
    required double amount,
    required DateTime settledAt,
    String note = '',
  }) async {
    final settlement = await _settlementRepository.recordSettlement(
      eventId: eventId,
      payerId: payerId,
      payeeId: payeeId,
      amount: amount,
      settledAt: settledAt,
      note: note,
    );
    await loadForEvent(eventId);
    return settlement;
  }

  Future<void> deleteSettlement(String settlementId, String eventId) async {
    await _settlementRepository.deleteSettlement(settlementId);
    await loadForEvent(eventId);
  }
}
