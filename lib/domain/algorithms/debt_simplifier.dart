import 'dart:math';
import '../../data/models/person_model.dart';
import '../models/balance_summary.dart';
import '../models/settlement_proposal.dart';

class DebtSimplifier {
  /// Takes a list of MemberBalance and returns the minimum number of
  /// settlement transactions required to settle all debts.
  static List<SettlementProposal> simplifyDebts(List<MemberBalance> balances) {
    // Collect creditors (net > 0) and debtors (net < 0)
    final List<_BalanceNode> creditors = [];
    final List<_BalanceNode> debtors = [];

    for (final member in balances) {
      final double net = member.netBalance;
      // Round to 2 decimals to prevent floating point epsilon issues
      final double roundedNet = (net * 100).round() / 100.0;

      if (roundedNet >= 0.01) {
        creditors.add(_BalanceNode(person: member.person, amount: roundedNet));
      } else if (roundedNet <= -0.01) {
        debtors.add(_BalanceNode(person: member.person, amount: roundedNet.abs()));
      }
    }

    final List<SettlementProposal> proposals = [];

    while (creditors.isNotEmpty && debtors.isNotEmpty) {
      // Sort creditors largest to smallest
      creditors.sort((a, b) => b.amount.compareTo(a.amount));
      // Sort debtors largest to smallest
      debtors.sort((a, b) => b.amount.compareTo(a.amount));

      final maxCreditor = creditors.first;
      final maxDebtor = debtors.first;

      final double settleAmount = min(maxCreditor.amount, maxDebtor.amount);
      final double roundedSettle = (settleAmount * 100).round() / 100.0;

      if (roundedSettle >= 0.01) {
        proposals.add(SettlementProposal(
          from: maxDebtor.person,
          to: maxCreditor.person,
          amount: roundedSettle,
        ));
      }

      maxCreditor.amount -= settleAmount;
      maxDebtor.amount -= settleAmount;

      if (maxCreditor.amount < 0.01) {
        creditors.removeAt(0);
      }
      if (maxDebtor.amount < 0.01) {
        debtors.removeAt(0);
      }
    }

    return proposals;
  }
}

class _BalanceNode {
  final PersonModel person;
  double amount;

  _BalanceNode({required this.person, required this.amount});
}
