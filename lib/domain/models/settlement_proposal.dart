import '../../data/models/person_model.dart';

class SettlementProposal {
  final PersonModel from;
  final PersonModel to;
  final double amount;

  const SettlementProposal({
    required this.from,
    required this.to,
    required this.amount,
  });

  @override
  String toString() => '${from.name} pays ${to.name}: $amount';
}
