import 'dart:math';
import '../../core/constants/app_constants.dart';
import '../../data/models/expense_split_model.dart';

class SplitCalculationResult {
  final bool isValid;
  final String? errorMessage;
  final List<ExpenseSplitModel> splits;

  const SplitCalculationResult({
    required this.isValid,
    this.errorMessage,
    required this.splits,
  });
}

class SplitCalculator {
  /// Calculate splits based on SplitType and input values
  static SplitCalculationResult calculateSplits({
    required String expenseId,
    required double totalAmount,
    required SplitType splitType,
    required List<String> selectedPersonIds,
    required Map<String, double> rawInputs, // personId -> exact/percent/share
    Map<String, int> personCounts = const {},
  }) {
    if (totalAmount <= 0) {
      return const SplitCalculationResult(
        isValid: false,
        errorMessage: 'Expense amount must be greater than zero.',
        splits: [],
      );
    }

    if (selectedPersonIds.isEmpty) {
      return const SplitCalculationResult(
        isValid: false,
        errorMessage: 'At least one person must be included in the split.',
        splits: [],
      );
    }

    switch (splitType) {
      case SplitType.equal:
        return _calculateEqualSplits(
          expenseId: expenseId,
          totalAmount: totalAmount,
          personIds: selectedPersonIds,
          personCounts: personCounts,
        );

      case SplitType.exact:
        return _calculateExactSplits(
          expenseId: expenseId,
          totalAmount: totalAmount,
          personIds: selectedPersonIds,
          exactAmounts: rawInputs,
        );

      case SplitType.percentage:
        return _calculatePercentageSplits(
          expenseId: expenseId,
          totalAmount: totalAmount,
          personIds: selectedPersonIds,
          percentages: rawInputs,
        );

      case SplitType.shares:
        return _calculateSharesSplits(
          expenseId: expenseId,
          totalAmount: totalAmount,
          personIds: selectedPersonIds,
          shares: rawInputs,
        );
    }
  }

  static SplitCalculationResult _calculateEqualSplits({
    required String expenseId,
    required double totalAmount,
    required List<String> personIds,
    Map<String, int> personCounts = const {},
  }) {
    final int totalWeight = personIds.fold<int>(
      0,
      (sum, id) => sum + max(1, personCounts[id] ?? 1),
    );

    if (totalWeight <= 0) {
      return const SplitCalculationResult(
        isValid: false,
        errorMessage: 'Total headcount must be greater than zero.',
        splits: [],
      );
    }

    final int totalCents = (totalAmount * 100).round();
    int allocatedCents = 0;
    final List<ExpenseSplitModel> splits = [];

    for (int i = 0; i < personIds.length; i++) {
      final personId = personIds[i];
      final weight = max(1, personCounts[personId] ?? 1);
      final cents = ((totalCents * weight) / totalWeight).round();
      allocatedCents += cents;

      splits.add(ExpenseSplitModel(
        id: '',
        expenseId: expenseId,
        personId: personId,
        allocatedAmount: cents / 100.0,
        rawValue: weight.toDouble(),
      ));
    }

    // Adjust any rounding cent difference on the first non-zero split
    final int centDiff = totalCents - allocatedCents;
    if (centDiff != 0 && splits.isNotEmpty) {
      final idx = splits.indexWhere((s) => s.allocatedAmount > 0);
      if (idx != -1) {
        final adjustedCents = (splits[idx].allocatedAmount * 100).round() + centDiff;
        splits[idx] = splits[idx].copyWith(allocatedAmount: max(0.0, adjustedCents / 100.0));
      }
    }

    return SplitCalculationResult(
      isValid: true,
      splits: splits,
    );
  }

  static SplitCalculationResult _calculateExactSplits({
    required String expenseId,
    required double totalAmount,
    required List<String> personIds,
    required Map<String, double> exactAmounts,
  }) {
    double runningSum = 0.0;
    final List<ExpenseSplitModel> splits = [];

    for (final personId in personIds) {
      final amount = exactAmounts[personId] ?? 0.0;
      if (amount < 0) {
        return const SplitCalculationResult(
          isValid: false,
          errorMessage: 'Amounts cannot be negative.',
          splits: [],
        );
      }
      runningSum += amount;
      splits.add(ExpenseSplitModel(
        id: '',
        expenseId: expenseId,
        personId: personId,
        allocatedAmount: (amount * 100).round() / 100.0,
        rawValue: amount,
      ));
    }

    final double diff = (totalAmount - runningSum).abs();
    if (diff > 0.05) {
      final sign = totalAmount > runningSum ? 'short' : 'over';
      final diffStr = diff.toStringAsFixed(2);
      return SplitCalculationResult(
        isValid: false,
        errorMessage:
            'Total split (${runningSum.toStringAsFixed(2)}) is $diffStr $sign of target (${totalAmount.toStringAsFixed(2)}).',
        splits: splits,
      );
    }

    return SplitCalculationResult(
      isValid: true,
      splits: splits,
    );
  }

  static SplitCalculationResult _calculatePercentageSplits({
    required String expenseId,
    required double totalAmount,
    required List<String> personIds,
    required Map<String, double> percentages,
  }) {
    double totalPercent = 0.0;
    for (final personId in personIds) {
      final pct = percentages[personId] ?? 0.0;
      if (pct < 0) {
        return const SplitCalculationResult(
          isValid: false,
          errorMessage: 'Percentages cannot be negative.',
          splits: [],
        );
      }
      totalPercent += pct;
    }

    if ((totalPercent - 100.0).abs() > 0.1) {
      return SplitCalculationResult(
        isValid: false,
        errorMessage:
            'Percentages must add up to 100% (currently ${totalPercent.toStringAsFixed(1)}%).',
        splits: [],
      );
    }

    final int targetCents = (totalAmount * 100).round();
    int allocatedCents = 0;
    final List<ExpenseSplitModel> splits = [];

    for (int i = 0; i < personIds.length; i++) {
      final personId = personIds[i];
      final pct = percentages[personId] ?? 0.0;
      final cents = ((targetCents * pct) / 100.0).round();
      allocatedCents += cents;

      splits.add(ExpenseSplitModel(
        id: '',
        expenseId: expenseId,
        personId: personId,
        allocatedAmount: cents / 100.0,
        rawValue: pct,
      ));
    }

    // Adjust any rounding cent difference on the first non-zero split
    final int centDiff = targetCents - allocatedCents;
    if (centDiff != 0 && splits.isNotEmpty) {
      final idx = splits.indexWhere((s) => s.allocatedAmount > 0);
      if (idx != -1) {
        final adjustedCents = (splits[idx].allocatedAmount * 100).round() + centDiff;
        splits[idx] = splits[idx].copyWith(allocatedAmount: max(0.0, adjustedCents / 100.0));
      }
    }

    return SplitCalculationResult(
      isValid: true,
      splits: splits,
    );
  }

  static SplitCalculationResult _calculateSharesSplits({
    required String expenseId,
    required double totalAmount,
    required List<String> personIds,
    required Map<String, double> shares,
  }) {
    double totalShares = 0.0;
    for (final personId in personIds) {
      final share = shares[personId] ?? 1.0;
      if (share < 0) {
        return const SplitCalculationResult(
          isValid: false,
          errorMessage: 'Shares cannot be negative.',
          splits: [],
        );
      }
      totalShares += share;
    }

    if (totalShares <= 0) {
      return const SplitCalculationResult(
        isValid: false,
        errorMessage: 'Total shares must be greater than zero.',
        splits: [],
      );
    }

    final int targetCents = (totalAmount * 100).round();
    int allocatedCents = 0;
    final List<ExpenseSplitModel> splits = [];

    for (int i = 0; i < personIds.length; i++) {
      final personId = personIds[i];
      final share = shares[personId] ?? 1.0;
      final cents = ((targetCents * share) / totalShares).round();
      allocatedCents += cents;

      splits.add(ExpenseSplitModel(
        id: '',
        expenseId: expenseId,
        personId: personId,
        allocatedAmount: cents / 100.0,
        rawValue: share,
      ));
    }

    // Adjust cent rounding on first non-zero split
    final int centDiff = targetCents - allocatedCents;
    if (centDiff != 0 && splits.isNotEmpty) {
      final idx = splits.indexWhere((s) => s.allocatedAmount > 0);
      if (idx != -1) {
        final adjustedCents = (splits[idx].allocatedAmount * 100).round() + centDiff;
        splits[idx] = splits[idx].copyWith(allocatedAmount: max(0.0, adjustedCents / 100.0));
      }
    }

    return SplitCalculationResult(
      isValid: true,
      splits: splits,
    );
  }
}
