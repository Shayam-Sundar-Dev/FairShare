import 'package:flutter_test/flutter_test.dart';
import 'package:fairshare/core/constants/app_constants.dart';
import 'package:fairshare/domain/algorithms/split_calculator.dart';

void main() {
  group('SplitCalculator - Equal Split', () {
    test('splits evenly without penny loss (100 / 3 = 33.34 + 33.33 + 33.33)', () {
      final result = SplitCalculator.calculateSplits(
        expenseId: 'exp1',
        totalAmount: 100.0,
        splitType: SplitType.equal,
        selectedPersonIds: ['p1', 'p2', 'p3'],
        rawInputs: {},
      );

      expect(result.isValid, isTrue);
      expect(result.splits.length, 3);

      final totalAllocated = result.splits
          .fold<double>(0.0, (sum, s) => sum + s.allocatedAmount);
      expect((totalAllocated - 100.0).abs() < 0.001, isTrue);
      expect(result.splits[0].allocatedAmount, 33.34);
      expect(result.splits[1].allocatedAmount, 33.33);
      expect(result.splits[2].allocatedAmount, 33.33);
    });

    test('splits evenly for 2 people (50 each)', () {
      final result = SplitCalculator.calculateSplits(
        expenseId: 'exp1',
        totalAmount: 50.0,
        splitType: SplitType.equal,
        selectedPersonIds: ['p1', 'p2'],
        rawInputs: {},
      );

      expect(result.isValid, isTrue);
      expect(result.splits[0].allocatedAmount, 25.0);
      expect(result.splits[1].allocatedAmount, 25.0);
    });

    test('splits proportionally to headcount (1, 2, 3, 4 persons for 1000 = 100, 200, 300, 400)', () {
      final result = SplitCalculator.calculateSplits(
        expenseId: 'exp1',
        totalAmount: 1000.0,
        splitType: SplitType.equal,
        selectedPersonIds: ['m1', 'm2', 'm3', 'm4'],
        rawInputs: {},
        personCounts: {'m1': 1, 'm2': 2, 'm3': 3, 'm4': 4},
      );

      expect(result.isValid, isTrue);
      expect(result.splits.length, 4);
      expect(result.splits[0].allocatedAmount, 100.0);
      expect(result.splits[1].allocatedAmount, 200.0);
      expect(result.splits[2].allocatedAmount, 300.0);
      expect(result.splits[3].allocatedAmount, 400.0);

      final totalAllocated = result.splits
          .fold<double>(0.0, (sum, s) => sum + s.allocatedAmount);
      expect((totalAllocated - 1000.0).abs() < 0.001, isTrue);
    });
  });

  group('SplitCalculator - Exact Split', () {
    test('validates matching exact split sum', () {
      final result = SplitCalculator.calculateSplits(
        expenseId: 'exp1',
        totalAmount: 150.0,
        splitType: SplitType.exact,
        selectedPersonIds: ['p1', 'p2'],
        rawInputs: {'p1': 100.0, 'p2': 50.0},
      );

      expect(result.isValid, isTrue);
      expect(result.splits[0].allocatedAmount, 100.0);
      expect(result.splits[1].allocatedAmount, 50.0);
    });

    test('rejects exact split when sum does not match', () {
      final result = SplitCalculator.calculateSplits(
        expenseId: 'exp1',
        totalAmount: 150.0,
        splitType: SplitType.exact,
        selectedPersonIds: ['p1', 'p2'],
        rawInputs: {'p1': 80.0, 'p2': 50.0},
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('short'));
    });
  });

  group('SplitCalculator - Percentage Split', () {
    test('calculates correct percentages and adjusts cent difference', () {
      final result = SplitCalculator.calculateSplits(
        expenseId: 'exp1',
        totalAmount: 100.0,
        splitType: SplitType.percentage,
        selectedPersonIds: ['p1', 'p2', 'p3'],
        rawInputs: {'p1': 50.0, 'p2': 30.0, 'p3': 20.0},
      );

      expect(result.isValid, isTrue);
      expect(result.splits[0].allocatedAmount, 50.0);
      expect(result.splits[1].allocatedAmount, 30.0);
      expect(result.splits[2].allocatedAmount, 20.0);
    });

    test('rejects when percentages do not sum to 100%', () {
      final result = SplitCalculator.calculateSplits(
        expenseId: 'exp1',
        totalAmount: 100.0,
        splitType: SplitType.percentage,
        selectedPersonIds: ['p1', 'p2'],
        rawInputs: {'p1': 40.0, 'p2': 50.0},
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('must add up to 100%'));
    });
  });

  group('SplitCalculator - Shares Split', () {
    test('calculates proportional shares (2:1 ratio for 300 = 200 and 100)', () {
      final result = SplitCalculator.calculateSplits(
        expenseId: 'exp1',
        totalAmount: 300.0,
        splitType: SplitType.shares,
        selectedPersonIds: ['p1', 'p2'],
        rawInputs: {'p1': 2.0, 'p2': 1.0},
      );

      expect(result.isValid, isTrue);
      expect(result.splits[0].allocatedAmount, 200.0);
      expect(result.splits[1].allocatedAmount, 100.0);
    });
  });
}
