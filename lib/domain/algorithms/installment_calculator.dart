import 'dart:math';
import 'package:uuid/uuid.dart';
import '../../data/models/person_model.dart';
import '../../data/models/trip_installment_model.dart';

class InstallmentMilestone {
  final int installmentNumber;
  final double expectedPerShare;
  final double totalExpected;
  final double totalCollected;
  final bool isFullyCollected;
  final List<TripInstallmentModel> memberInstallments;

  const InstallmentMilestone({
    required this.installmentNumber,
    required this.expectedPerShare,
    required this.totalExpected,
    required this.totalCollected,
    required this.isFullyCollected,
    required this.memberInstallments,
  });
}

class InstallmentPlanSummary {
  final double totalBudget;
  final double totalCollected;
  final double remainingBudget;
  final int totalInstallments;
  final int completedMilestonesCount;
  final List<InstallmentMilestone> milestones;
  final List<TripInstallmentModel> allInstallments;

  const InstallmentPlanSummary({
    required this.totalBudget,
    required this.totalCollected,
    required this.remainingBudget,
    required this.totalInstallments,
    required this.completedMilestonesCount,
    required this.milestones,
    required this.allInstallments,
  });

  double get progressPercentage =>
      totalBudget > 0 ? (totalCollected / totalBudget).clamp(0.0, 1.0) : 0.0;
}

class InstallmentCalculator {
  static const Uuid _uuid = Uuid();

  /// Calculates dynamic installment amounts and rebalances remaining installments
  /// when participants are added, removed, or have modified quantities.
  static InstallmentPlanSummary calculatePlan({
    required String eventId,
    required double estimatedBudget,
    required int installmentsCount,
    required List<PersonModel> members,
    List<TripInstallmentModel> existingInstallments = const [],
  }) {
    final int safeInstallmentsCount = max(1, installmentsCount);
    final int totalShares = members.fold<int>(0, (sum, m) => sum + max(1, m.count));

    // Map existing installments by "${installmentNumber}_${personId}"
    final Map<String, TripInstallmentModel> existingMap = {
      for (final inst in existingInstallments)
        '${inst.installmentNumber}_${inst.personId}': inst,
    };

    // Calculate total already paid across all existing records
    double totalCollected = 0.0;
    for (final inst in existingInstallments) {
      if (inst.isPaid) {
        totalCollected += inst.paidAmount > 0 ? inst.paidAmount : inst.expectedAmount;
      }
    }

    // Determine which installment numbers are already fully closed/locked
    final Set<int> fullyPaidInstallmentNumbers = {};
    for (int num = 1; num <= safeInstallmentsCount; num++) {
      final forNum = existingInstallments.where((i) => i.installmentNumber == num).toList();
      if (forNum.isNotEmpty && forNum.every((i) => i.isPaid)) {
        fullyPaidInstallmentNumbers.add(num);
      }
    }

    // Calculate remaining target to be distributed over unpaid installments
    double remainingBudget = max(0.0, estimatedBudget - totalCollected);
    final int remainingInstallmentCount =
        max(1, safeInstallmentsCount - fullyPaidInstallmentNumbers.length);

    final double perShareForRemaining = totalShares > 0
        ? remainingBudget / (remainingInstallmentCount * totalShares)
        : 0.0;

    final List<InstallmentMilestone> milestones = [];
    final List<TripInstallmentModel> allGenerated = [];

    for (int instNum = 1; instNum <= safeInstallmentsCount; instNum++) {
      final isLocked = fullyPaidInstallmentNumbers.contains(instNum);
      final List<TripInstallmentModel> milestoneItems = [];
      double milestoneExpected = 0.0;
      double milestoneCollected = 0.0;

      for (final member in members) {
        final key = '${instNum}_${member.id}';
        final existing = existingMap[key];

        final double expected = isLocked && existing != null
            ? existing.expectedAmount
            : (existing?.isPaid == true
                ? existing!.expectedAmount
                : (perShareForRemaining * max(1, member.count)));

        final double roundedExpected = (expected * 100).round() / 100.0;
        final bool isPaid = existing?.isPaid ?? false;
        final double paidAmount = isPaid
            ? (existing?.paidAmount != null && existing!.paidAmount > 0
                ? existing.paidAmount
                : roundedExpected)
            : 0.0;

        final item = TripInstallmentModel(
          id: existing?.id ?? _uuid.v4(),
          eventId: eventId,
          installmentNumber: instNum,
          personId: member.id,
          expectedAmount: roundedExpected,
          paidAmount: paidAmount,
          isPaid: isPaid,
          paidAt: existing?.paidAt,
          notes: existing?.notes ?? '',
        );

        milestoneItems.add(item);
        allGenerated.add(item);
        milestoneExpected += item.expectedAmount;
        milestoneCollected += item.paidAmount;
      }

      final bool isMilestoneFullyCollected =
          milestoneItems.isNotEmpty && milestoneItems.every((i) => i.isPaid);

      milestones.add(InstallmentMilestone(
        installmentNumber: instNum,
        expectedPerShare: isLocked
            ? (milestoneExpected / max(1, totalShares))
            : perShareForRemaining,
        totalExpected: milestoneExpected,
        totalCollected: milestoneCollected,
        isFullyCollected: isMilestoneFullyCollected,
        memberInstallments: milestoneItems,
      ));
    }

    return InstallmentPlanSummary(
      totalBudget: estimatedBudget,
      totalCollected: totalCollected,
      remainingBudget: remainingBudget,
      totalInstallments: safeInstallmentsCount,
      completedMilestonesCount: fullyPaidInstallmentNumbers.length,
      milestones: milestones,
      allInstallments: allGenerated,
    );
  }
}
