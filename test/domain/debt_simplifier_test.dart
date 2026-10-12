import 'package:flutter_test/flutter_test.dart';
import 'package:fairshare/data/models/person_model.dart';
import 'package:fairshare/domain/algorithms/debt_simplifier.dart';
import 'package:fairshare/domain/models/balance_summary.dart';

void main() {
  group('DebtSimplifier', () {
    const alice = PersonModel(id: '1', name: 'Alice', phoneNumber: '111');
    const bob = PersonModel(id: '2', name: 'Bob', phoneNumber: '222');
    const charlie = PersonModel(id: '3', name: 'Charlie', phoneNumber: '333');

    test('simplifies 2-person debt correctly', () {
      // Alice paid 100, split 50/50 with Bob. Alice net = +50, Bob net = -50.
      final balances = [
        const MemberBalance(
          person: alice,
          totalPaid: 100,
          totalOwed: 50,
          settlementPaid: 0,
          settlementReceived: 0,
        ),
        const MemberBalance(
          person: bob,
          totalPaid: 0,
          totalOwed: 50,
          settlementPaid: 0,
          settlementReceived: 0,
        ),
      ];

      final proposals = DebtSimplifier.simplifyDebts(balances);
      expect(proposals.length, 1);
      expect(proposals.first.from.name, 'Bob');
      expect(proposals.first.to.name, 'Alice');
      expect(proposals.first.amount, 50.0);
    });

    test('simplifies 3-person circular/chained debt into minimal transactions', () {
      // Alice is owed 40 (+40)
      // Bob is owed 10 (+10)
      // Charlie owes 50 (-50)
      final balances = [
        const MemberBalance(
          person: alice,
          totalPaid: 40,
          totalOwed: 0,
          settlementPaid: 0,
          settlementReceived: 0,
        ),
        const MemberBalance(
          person: bob,
          totalPaid: 10,
          totalOwed: 0,
          settlementPaid: 0,
          settlementReceived: 0,
        ),
        const MemberBalance(
          person: charlie,
          totalPaid: 0,
          totalOwed: 50,
          settlementPaid: 0,
          settlementReceived: 0,
        ),
      ];

      final proposals = DebtSimplifier.simplifyDebts(balances);
      // Charlie should pay 40 to Alice and 10 to Bob
      expect(proposals.length, 2);
      final totalSettled = proposals.fold<double>(0, (sum, p) => sum + p.amount);
      expect(totalSettled, 50.0);

      expect(proposals.any((p) => p.from.name == 'Charlie' && p.to.name == 'Alice' && p.amount == 40.0), isTrue);
      expect(proposals.any((p) => p.from.name == 'Charlie' && p.to.name == 'Bob' && p.amount == 10.0), isTrue);
    });

    test('returns empty when everyone is settled', () {
      final balances = [
        const MemberBalance(
          person: alice,
          totalPaid: 50,
          totalOwed: 50,
          settlementPaid: 0,
          settlementReceived: 0,
        ),
        const MemberBalance(
          person: bob,
          totalPaid: 50,
          totalOwed: 50,
          settlementPaid: 0,
          settlementReceived: 0,
        ),
      ];

      final proposals = DebtSimplifier.simplifyDebts(balances);
      expect(proposals.isEmpty, isTrue);
    });
  });
}
