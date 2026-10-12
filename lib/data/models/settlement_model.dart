class SettlementModel {
  final String id;
  final String eventId;
  final String payerId;
  final String payeeId;
  final double amount;
  final DateTime settledAt;
  final String note;

  const SettlementModel({
    required this.id,
    required this.eventId,
    required this.payerId,
    required this.payeeId,
    required this.amount,
    required this.settledAt,
    this.note = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'event_id': eventId,
      'payer_id': payerId,
      'payee_id': payeeId,
      'amount': amount,
      'settled_at': settledAt.millisecondsSinceEpoch,
      'note': note,
    };
  }

  factory SettlementModel.fromMap(Map<String, dynamic> map) {
    return SettlementModel(
      id: map['id'] as String,
      eventId: map['event_id'] as String,
      payerId: map['payer_id'] as String,
      payeeId: map['payee_id'] as String,
      amount: (map['amount'] as num).toDouble(),
      settledAt: DateTime.fromMillisecondsSinceEpoch(map['settled_at'] as int),
      note: map['note'] as String? ?? '',
    );
  }

  SettlementModel copyWith({
    String? id,
    String? eventId,
    String? payerId,
    String? payeeId,
    double? amount,
    DateTime? settledAt,
    String? note,
  }) {
    return SettlementModel(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      payerId: payerId ?? this.payerId,
      payeeId: payeeId ?? this.payeeId,
      amount: amount ?? this.amount,
      settledAt: settledAt ?? this.settledAt,
      note: note ?? this.note,
    );
  }
}
