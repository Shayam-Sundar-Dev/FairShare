class ExpenseSplitModel {
  final String id;
  final String expenseId;
  final String personId;
  final double allocatedAmount;
  final double rawValue; // percentage, exact, or shares value inputted

  const ExpenseSplitModel({
    required this.id,
    required this.expenseId,
    required this.personId,
    required this.allocatedAmount,
    required this.rawValue,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'expense_id': expenseId,
      'person_id': personId,
      'allocated_amount': allocatedAmount,
      'raw_value': rawValue,
    };
  }

  factory ExpenseSplitModel.fromMap(Map<String, dynamic> map) {
    return ExpenseSplitModel(
      id: map['id'] as String,
      expenseId: map['expense_id'] as String,
      personId: map['person_id'] as String,
      allocatedAmount: (map['allocated_amount'] as num).toDouble(),
      rawValue: (map['raw_value'] as num).toDouble(),
    );
  }

  ExpenseSplitModel copyWith({
    String? id,
    String? expenseId,
    String? personId,
    double? allocatedAmount,
    double? rawValue,
  }) {
    return ExpenseSplitModel(
      id: id ?? this.id,
      expenseId: expenseId ?? this.expenseId,
      personId: personId ?? this.personId,
      allocatedAmount: allocatedAmount ?? this.allocatedAmount,
      rawValue: rawValue ?? this.rawValue,
    );
  }
}
