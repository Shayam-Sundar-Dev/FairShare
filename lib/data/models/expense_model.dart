import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import 'expense_split_model.dart';

enum ExpenseApprovalStatus {
  approved('approved', 'Approved'),
  pending('pending', 'Pending Approval'),
  rejected('rejected', 'Rejected');

  final String dbValue;
  final String displayName;
  const ExpenseApprovalStatus(this.dbValue, this.displayName);

  static ExpenseApprovalStatus fromDbValue(String? value) {
    if (value == null) return ExpenseApprovalStatus.approved;
    for (final s in ExpenseApprovalStatus.values) {
      if (s.dbValue == value || s.name == value) return s;
    }
    return ExpenseApprovalStatus.approved;
  }
}

class ExpenseModel {
  static const String committeePayerId = 'committee_pool';

  final String id;
  final String eventId;
  final String payerId;
  final String title;
  final double amount;
  final String category;
  final SplitType splitType;
  final DateTime date;
  final String? location;
  final double? latitude;
  final double? longitude;
  final String? receiptPath;
  final List<ExpenseSplitModel> splits;
  final ExpenseApprovalStatus approvalStatus;
  final String? submittedByPersonId;
  final String? submittedByName;
  final String? rejectionReason;
  final DateTime? approvedAt;
  final bool isCommitteeSpend;

  const ExpenseModel({
    required this.id,
    required this.eventId,
    required this.payerId,
    required this.title,
    required this.amount,
    required this.category,
    required this.splitType,
    required this.date,
    this.location,
    this.latitude,
    this.longitude,
    this.receiptPath,
    this.splits = const [],
    this.approvalStatus = ExpenseApprovalStatus.approved,
    this.submittedByPersonId,
    this.submittedByName,
    this.rejectionReason,
    this.approvedAt,
    this.isCommitteeSpend = false,
  });

  bool get isApproved => approvalStatus == ExpenseApprovalStatus.approved;
  bool get isPending => approvalStatus == ExpenseApprovalStatus.pending;
  bool get isRejected => approvalStatus == ExpenseApprovalStatus.rejected;
  bool get isFromCommittee => isCommitteeSpend || payerId == committeePayerId;

  Map<String, dynamic> toMap({bool includeSplits = false}) {
    final map = <String, dynamic>{
      'id': id,
      'event_id': eventId,
      'payer_id': payerId,
      'title': title,
      'amount': amount,
      'category': category,
      'split_type': splitType.dbValue,
      'date': date.millisecondsSinceEpoch,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'receipt_path': receiptPath,
      'approval_status': approvalStatus.dbValue,
      'submitted_by_person_id': submittedByPersonId,
      'submitted_by_name': submittedByName,
      'rejection_reason': rejectionReason,
      'approved_at': approvedAt?.millisecondsSinceEpoch,
      'is_committee_spend': isCommitteeSpend || payerId == committeePayerId ? 1 : 0,
    };
    if (includeSplits && splits.isNotEmpty) {
      map['splits'] = splits.map((s) => s.toMap()).toList();
    }
    return map;
  }

  factory ExpenseModel.fromMap(
    Map<String, dynamic> map, {
    List<ExpenseSplitModel>? splits,
  }) {
    List<ExpenseSplitModel> resolvedSplits = splits ?? const [];
    if (splits == null && map['splits'] is List) {
      resolvedSplits = (map['splits'] as List)
          .map((s) => ExpenseSplitModel.fromMap(Map<String, dynamic>.from(s as Map)))
          .toList();
    }

    final rawAmount = map['amount'];
    final double parsedAmount = rawAmount is num
        ? rawAmount.toDouble()
        : (double.tryParse(rawAmount?.toString() ?? '') ?? 0.0);

    final rawDate = map['date'];
    final DateTime parsedDate = rawDate is int
        ? DateTime.fromMillisecondsSinceEpoch(rawDate)
        : (rawDate is String
            ? (DateTime.tryParse(rawDate) ?? DateTime.now())
            : DateTime.now());

    return ExpenseModel(
      id: (map['id'] as String?)?.isNotEmpty == true
          ? map['id'] as String
          : const Uuid().v4(),
      eventId: (map['event_id'] as String?) ?? '',
      payerId: (map['payer_id'] as String?) ?? '',
      title: (map['title'] as String?) ?? 'Expense',
      amount: parsedAmount,
      category: (map['category'] as String?) ?? 'General',
      splitType: SplitTypeExtension.fromDbValue(map['split_type'] as String?),
      date: parsedDate,
      location: map['location'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      receiptPath: map['receipt_path'] as String?,
      splits: resolvedSplits,
      approvalStatus: ExpenseApprovalStatus.fromDbValue(map['approval_status'] as String?),
      submittedByPersonId: map['submitted_by_person_id'] as String?,
      submittedByName: map['submitted_by_name'] as String?,
      rejectionReason: map['rejection_reason'] as String?,
      approvedAt: map['approved_at'] != null
          ? (map['approved_at'] is int
              ? DateTime.fromMillisecondsSinceEpoch(map['approved_at'] as int)
              : DateTime.tryParse(map['approved_at'].toString()))
          : null,
      isCommitteeSpend: (map['is_committee_spend'] as int? ?? 0) == 1 ||
          map['payer_id'] == committeePayerId,
    );
  }

  ExpenseModel copyWith({
    String? id,
    String? eventId,
    String? payerId,
    String? title,
    double? amount,
    String? category,
    SplitType? splitType,
    DateTime? date,
    String? location,
    double? latitude,
    double? longitude,
    String? receiptPath,
    bool clearReceiptPath = false,
    List<ExpenseSplitModel>? splits,
    ExpenseApprovalStatus? approvalStatus,
    String? submittedByPersonId,
    String? submittedByName,
    String? rejectionReason,
    DateTime? approvedAt,
    bool? isCommitteeSpend,
  }) {
    return ExpenseModel(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      payerId: payerId ?? this.payerId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      splitType: splitType ?? this.splitType,
      date: date ?? this.date,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      receiptPath: clearReceiptPath ? null : (receiptPath ?? this.receiptPath),
      splits: splits ?? this.splits,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      submittedByPersonId: submittedByPersonId ?? this.submittedByPersonId,
      submittedByName: submittedByName ?? this.submittedByName,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      approvedAt: approvedAt ?? this.approvedAt,
      isCommitteeSpend: isCommitteeSpend ?? this.isCommitteeSpend,
    );
  }
}
