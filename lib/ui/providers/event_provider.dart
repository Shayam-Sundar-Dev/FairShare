import 'package:flutter/material.dart';
import '../../data/models/event_model.dart';
import '../../data/models/trip_installment_model.dart';
import '../../data/repositories/event_repository.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/settlement_repository.dart';
import '../../data/repositories/trip_installment_repository.dart';
import '../../domain/algorithms/debt_simplifier.dart';
import '../../domain/algorithms/installment_calculator.dart';
import '../../domain/models/balance_summary.dart';
import '../../domain/models/settlement_proposal.dart';

class EventProvider extends ChangeNotifier {
  final EventRepository _eventRepository;
  final ExpenseRepository _expenseRepository;
  final SettlementRepository _settlementRepository;
  final TripInstallmentRepository _installmentRepository;

  List<EventModel> _events = [];
  EventModel? _selectedEvent;
  final Map<String, EventSummaryData> _summaries = {};
  EventFinancialSummary? _currentFinancialSummary;
  List<SettlementProposal> _settlementProposals = [];
  List<TripInstallmentModel> _installments = [];
  InstallmentPlanSummary? _installmentPlanSummary;
  bool _isLoading = false;
  String? _errorMessage;

  EventProvider({
    EventRepository? eventRepository,
    ExpenseRepository? expenseRepository,
    SettlementRepository? settlementRepository,
    TripInstallmentRepository? installmentRepository,
  })  : _eventRepository = eventRepository ?? EventRepository(),
        _expenseRepository = expenseRepository ?? ExpenseRepository(),
        _settlementRepository = settlementRepository ?? SettlementRepository(),
        _installmentRepository = installmentRepository ?? TripInstallmentRepository();

  List<EventModel> get events => _events;
  List<EventModel> get activeEvents => _events.where((e) => !e.isArchived).toList();
  List<EventModel> get archivedEvents => _events.where((e) => e.isArchived).toList();
  List<EventModel> get planningEvents => _events.where((e) => e.isPlanning && !e.isArchived).toList();
  EventModel? get selectedEvent => _selectedEvent;
  Map<String, EventSummaryData> get summaries => _summaries;
  EventFinancialSummary? get currentFinancialSummary => _currentFinancialSummary;
  List<SettlementProposal> get settlementProposals => _settlementProposals;
  List<TripInstallmentModel> get installments => _installments;
  InstallmentPlanSummary? get installmentPlanSummary => _installmentPlanSummary;
  double get totalCommitteeFundPaid => _currentFinancialSummary?.committeeFundCollected ?? 0.0;
  double get totalCommitteeFundSpent => _currentFinancialSummary?.committeeFundSpent ?? 0.0;
  double get committeePoolBalance =>
      (_currentFinancialSummary?.committeeFundCollected ?? 0.0) -
      (_currentFinancialSummary?.committeeFundSpent ?? 0.0);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadEvents() async {
    _isLoading = true;
    notifyListeners();

    try {
      _events = await _eventRepository.getAllEvents();
      for (final event in _events) {
        final summary = await _eventRepository.getEventSummary(event.id);
        _summaries[event.id] = summary;
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<EventModel?> selectEvent(String eventId) async {
    try {
      _selectedEvent = await _eventRepository.getEventById(eventId);
      if (_selectedEvent != null) {
        await loadTripInstallments(eventId);
        await computeFinancials(eventId);
      }
      notifyListeners();
      return _selectedEvent;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> loadTripInstallments(String eventId) async {
    final event = _selectedEvent?.id == eventId
        ? _selectedEvent
        : await _eventRepository.getEventById(eventId);
    if (event == null) return;

    _installments = await _installmentRepository.getInstallmentsForEvent(eventId);

    if (event.isPlanning && event.estimatedBudget > 0) {
      _installmentPlanSummary = InstallmentCalculator.calculatePlan(
        eventId: event.id,
        estimatedBudget: event.estimatedBudget,
        installmentsCount: event.installmentsCount,
        members: event.members,
        existingInstallments: _installments,
      );

      // If existing DB records were missing or out of sync with members, persist the generated ones
      if (_installments.isEmpty && _installmentPlanSummary != null) {
        _installments = _installmentPlanSummary!.allInstallments;
        await _installmentRepository.batchSaveInstallments(
          eventId,
          _installments,
        );
      }
    } else {
      _installmentPlanSummary = null;
    }
    notifyListeners();
  }

  Future<void> toggleInstallmentPaid(TripInstallmentModel installment) async {
    final newPaid = !installment.isPaid;
    final paidAmount = newPaid ? installment.expectedAmount : 0.0;
    await _installmentRepository.setInstallmentPaidStatus(
      id: installment.id,
      isPaid: newPaid,
      paidAmount: paidAmount,
    );
    await loadTripInstallments(installment.eventId);
    await computeFinancials(installment.eventId);
  }

  Future<void> startTrip(String eventId) async {
    await _eventRepository.updateEventStatus(eventId, 'active');
    await loadEvents();
    if (_selectedEvent?.id == eventId) {
      await selectEvent(eventId);
    }
  }

  Future<EventModel> createEvent({
    required String title,
    required String eventType,
    String currency = '₹',
    String description = '',
    required List<String> memberPersonIds,
    Map<String, int> memberCounts = const {},
    String status = 'active',
    double estimatedBudget = 0.0,
    int installmentsCount = 1,
    String? creatorId,
    String? creatorEmail,
  }) async {
    final event = await _eventRepository.createEvent(
      title: title,
      eventType: eventType,
      currency: currency,
      description: description,
      memberPersonIds: memberPersonIds,
      memberCounts: memberCounts,
      status: status,
      estimatedBudget: estimatedBudget,
      installmentsCount: installmentsCount,
      creatorId: creatorId,
      creatorEmail: creatorEmail,
    );

    if (status == 'planning' && estimatedBudget > 0) {
      final plan = InstallmentCalculator.calculatePlan(
        eventId: event.id,
        estimatedBudget: estimatedBudget,
        installmentsCount: installmentsCount,
        members: event.members,
      );
      await _installmentRepository.batchSaveInstallments(
        event.id,
        plan.allInstallments,
      );
    }

    await loadEvents();
    return event;
  }

  Future<void> updateEvent({
    required EventModel event,
    required List<String> memberPersonIds,
    Map<String, int> memberCounts = const {},
  }) async {
    await _eventRepository.updateEvent(
      event: event,
      memberPersonIds: memberPersonIds,
      memberCounts: memberCounts,
    );

    if (event.isPlanning && event.estimatedBudget > 0) {
      final updatedEvent = await _eventRepository.getEventById(event.id);
      if (updatedEvent != null) {
        final existing = await _installmentRepository.getInstallmentsForEvent(event.id);
        final plan = InstallmentCalculator.calculatePlan(
          eventId: event.id,
          estimatedBudget: event.estimatedBudget,
          installmentsCount: event.installmentsCount,
          members: updatedEvent.members,
          existingInstallments: existing,
        );
        await _installmentRepository.batchSaveInstallments(
          event.id,
          plan.allInstallments,
        );
      }
    }

    await loadEvents();
    if (_selectedEvent?.id == event.id) {
      await selectEvent(event.id);
    }
  }

  Future<void> addMemberToEvent(String eventId, String personId) async {
    await _eventRepository.addMemberToEvent(eventId, personId);
    if (_selectedEvent?.id == eventId) {
      await selectEvent(eventId);
    }
    await loadEvents();
  }

  Future<void> deleteEvent(String id) async {
    await _eventRepository.deleteEvent(id);
    if (_selectedEvent?.id == id) {
      _selectedEvent = null;
    }
    await loadEvents();
  }

  /// Refreshes a single event from the DB and updates it in the in-memory list.
  /// Much cheaper than a full loadEvents() — use after syncs to update sync timestamps.
  Future<void> refreshEventInList(String eventId) async {
    try {
      final updated = await _eventRepository.getEventById(eventId);
      if (updated == null) return;
      final idx = _events.indexWhere((e) => e.id == eventId);
      if (idx >= 0) {
        _events[idx] = updated;
      }
      if (_selectedEvent?.id == eventId) {
        _selectedEvent = updated;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> completeSplitAndArchive(String eventId) async {
    await _eventRepository.setEventArchived(eventId, true);
    await loadEvents();
    if (_selectedEvent?.id == eventId) {
      await selectEvent(eventId);
    }
  }

  Future<void> unarchiveEvent(String eventId) async {
    await _eventRepository.setEventArchived(eventId, false);
    await loadEvents();
    if (_selectedEvent?.id == eventId) {
      await selectEvent(eventId);
    }
  }

  Future<void> computeFinancials(String eventId) async {
    final event = await _eventRepository.getEventById(eventId);
    if (event == null) return;

    final expenses = await _expenseRepository.getExpensesForEvent(eventId);
    final settlements = await _settlementRepository.getSettlementsForEvent(eventId);
    final installments = await _installmentRepository.getInstallmentsForEvent(eventId);

    final Map<String, double> totalPaidMap = {};
    final Map<String, double> totalOwedMap = {};
    final Map<String, double> settledPaidMap = {};
    final Map<String, double> settledReceivedMap = {};

    double totalSpend = 0.0;
    double committeeFundCollected = 0.0;
    double committeeFundSpent = 0.0;

    for (final member in event.members) {
      totalPaidMap[member.id] = 0.0;
      totalOwedMap[member.id] = 0.0;
      settledPaidMap[member.id] = 0.0;
      settledReceivedMap[member.id] = 0.0;
    }

    // Tally paid installments into member credits and committee pool
    for (final inst in installments) {
      if (inst.isPaid) {
        final amount = inst.paidAmount > 0 ? inst.paidAmount : inst.expectedAmount;
        committeeFundCollected += amount;
        totalPaidMap[inst.personId] = (totalPaidMap[inst.personId] ?? 0.0) + amount;
      }
    }

    for (final exp in expenses) {
      if (!exp.isApproved) continue; // Only approved expenses count

      totalSpend += exp.amount;

      if (exp.isFromCommittee) {
        committeeFundSpent += exp.amount;
      } else {
        totalPaidMap[exp.payerId] = (totalPaidMap[exp.payerId] ?? 0.0) + exp.amount;
      }

      for (final split in exp.splits) {
        totalOwedMap[split.personId] =
            (totalOwedMap[split.personId] ?? 0.0) + split.allocatedAmount;
      }
    }

    for (final set in settlements) {
      settledPaidMap[set.payerId] =
          (settledPaidMap[set.payerId] ?? 0.0) + set.amount;
      settledReceivedMap[set.payeeId] =
          (settledReceivedMap[set.payeeId] ?? 0.0) + set.amount;
    }

    final List<MemberBalance> memberBalances = [];
    for (final member in event.members) {
      memberBalances.add(MemberBalance(
        person: member,
        totalPaid: totalPaidMap[member.id] ?? 0.0,
        totalOwed: totalOwedMap[member.id] ?? 0.0,
        settlementPaid: settledPaidMap[member.id] ?? 0.0,
        settlementReceived: settledReceivedMap[member.id] ?? 0.0,
      ));
    }

    _currentFinancialSummary = EventFinancialSummary(
      totalSpend: totalSpend,
      memberBalances: memberBalances,
      committeeFundCollected: committeeFundCollected,
      committeeFundSpent: committeeFundSpent,
    );

    _settlementProposals = DebtSimplifier.simplifyDebts(memberBalances);
    notifyListeners();
  }
}
