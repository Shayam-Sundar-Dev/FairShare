import 'package:flutter_test/flutter_test.dart';
import 'package:fairshare/data/models/person_model.dart';
import 'package:fairshare/data/models/trip_installment_model.dart';
import 'package:fairshare/domain/algorithms/installment_calculator.dart';

void main() {
  group('InstallmentCalculator', () {
    const member1 = PersonModel(id: 'm1', name: 'User 1', phoneNumber: '111', count: 1);
    const member2 = PersonModel(id: 'm2', name: 'User 2', phoneNumber: '222', count: 2);

    test('calculates correct installments based on headcounts and milestones', () {
      // Total budget 6000, 2 milestones, member1 has 1 share, member2 has 2 shares (total 3 shares)
      // Per milestone budget = 3000
      // Member1 share per milestone = 1000
      // Member2 share per milestone = 2000
      final plan = InstallmentCalculator.calculatePlan(
        eventId: 'event1',
        estimatedBudget: 6000.0,
        installmentsCount: 2,
        members: [member1, member2],
      );

      expect(plan.totalBudget, 6000.0);
      expect(plan.totalInstallments, 2);
      expect(plan.milestones.length, 2);

      final m1 = plan.milestones[0];
      expect(m1.memberInstallments.length, 2);
      expect(m1.memberInstallments[0].expectedAmount, 1000.0);
      expect(m1.memberInstallments[1].expectedAmount, 2000.0);
      expect(m1.totalExpected, 3000.0);
      expect(m1.isFullyCollected, isFalse);

      final m2 = plan.milestones[1];
      expect(m2.memberInstallments[0].expectedAmount, 1000.0);
      expect(m2.memberInstallments[1].expectedAmount, 2000.0);
    });

    test('rebalances remaining installments when a milestone is completed', () {
      // Budget: 6000, 2 installments.
      // Milestone 1 is completely paid (3000 paid).
      final existingInstallments = [
        const TripInstallmentModel(
          id: 'i1',
          eventId: 'event1',
          installmentNumber: 1,
          personId: 'm1',
          expectedAmount: 1000.0,
          paidAmount: 1000.0,
          isPaid: true,
        ),
        const TripInstallmentModel(
          id: 'i2',
          eventId: 'event1',
          installmentNumber: 1,
          personId: 'm2',
          expectedAmount: 2000.0,
          paidAmount: 2000.0,
          isPaid: true,
        ),
      ];

      final plan = InstallmentCalculator.calculatePlan(
        eventId: 'event1',
        estimatedBudget: 6000.0,
        installmentsCount: 2,
        members: [member1, member2],
        existingInstallments: existingInstallments,
      );

      expect(plan.totalCollected, 3000.0);
      expect(plan.remainingBudget, 3000.0);
      expect(plan.completedMilestonesCount, 1);
      expect(plan.milestones[0].isFullyCollected, isTrue);
      expect(plan.milestones[1].isFullyCollected, isFalse);
    });
  });
}
