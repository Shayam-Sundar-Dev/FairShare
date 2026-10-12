import '../../data/models/person_model.dart';

class MemberBalance {
  final PersonModel person;
  final double totalPaid;
  final double totalOwed;
  final double settlementPaid;
  final double settlementReceived;

  const MemberBalance({
    required this.person,
    required this.totalPaid,
    required this.totalOwed,
    required this.settlementPaid,
    required this.settlementReceived,
  });

  /// Net balance:
  /// Positive (+) means the person is owed money (creditor).
  /// Negative (-) means the person owes money (debtor).
  /// Zero (0) means the person is settled up.
  double get netBalance =>
      (totalPaid + settlementPaid) - (totalOwed + settlementReceived);

  bool get isSettled => netBalance.abs() < 0.01;
  bool get isOwed => netBalance >= 0.01;
  bool get owes => netBalance <= -0.01;
}

class EventFinancialSummary {
  final double totalSpend;
  final List<MemberBalance> memberBalances;
  final double committeeFundCollected;
  final double committeeFundSpent;

  const EventFinancialSummary({
    required this.totalSpend,
    required this.memberBalances,
    this.committeeFundCollected = 0.0,
    this.committeeFundSpent = 0.0,
  });

  double get committeeFundBalance =>
      (committeeFundCollected - committeeFundSpent).clamp(0.0, double.infinity);

  bool get hasCommitteeFund => committeeFundCollected > 0;

  MemberBalance? getBalanceForPerson(String personId) {
    try {
      return memberBalances.firstWhere((b) => b.person.id == personId);
    } catch (_) {
      return null;
    }
  }
}
