class TripInstallmentModel {
  final String id;
  final String eventId;
  final int installmentNumber;
  final String personId;
  final double expectedAmount;
  final double paidAmount;
  final bool isPaid;
  final DateTime? paidAt;
  final String notes;

  const TripInstallmentModel({
    required this.id,
    required this.eventId,
    required this.installmentNumber,
    required this.personId,
    required this.expectedAmount,
    this.paidAmount = 0.0,
    this.isPaid = false,
    this.paidAt,
    this.notes = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'event_id': eventId,
      'installment_number': installmentNumber,
      'person_id': personId,
      'expected_amount': expectedAmount,
      'paid_amount': paidAmount,
      'is_paid': isPaid ? 1 : 0,
      'paid_at': paidAt?.millisecondsSinceEpoch,
      'notes': notes,
    };
  }

  factory TripInstallmentModel.fromMap(Map<String, dynamic> map) {
    return TripInstallmentModel(
      id: map['id'] as String,
      eventId: map['event_id'] as String,
      installmentNumber: (map['installment_number'] as int?) ?? 1,
      personId: map['person_id'] as String,
      expectedAmount: (map['expected_amount'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0.0,
      isPaid: (map['is_paid'] as int? ?? 0) == 1,
      paidAt: map['paid_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['paid_at'] as int)
          : null,
      notes: map['notes'] as String? ?? '',
    );
  }

  TripInstallmentModel copyWith({
    String? id,
    String? eventId,
    int? installmentNumber,
    String? personId,
    double? expectedAmount,
    double? paidAmount,
    bool? isPaid,
    DateTime? paidAt,
    String? notes,
  }) {
    return TripInstallmentModel(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      installmentNumber: installmentNumber ?? this.installmentNumber,
      personId: personId ?? this.personId,
      expectedAmount: expectedAmount ?? this.expectedAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      isPaid: isPaid ?? this.isPaid,
      paidAt: paidAt ?? this.paidAt,
      notes: notes ?? this.notes,
    );
  }
}
