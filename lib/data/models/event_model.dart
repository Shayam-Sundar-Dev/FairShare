import 'person_model.dart';

class EventModel {
  final String id;
  final String title;
  final String eventType;
  final String currency;
  final String description;
  final DateTime createdAt;
  final bool isArchived;
  final String status;
  final double estimatedBudget;
  final int installmentsCount;
  final List<PersonModel> members;
  final String? creatorId;
  final String? creatorEmail;
  final String? driveFileId;
  final String? shareCode;
  final bool isShared;
  final DateTime? lastSyncedAt;

  const EventModel({
    required this.id,
    required this.title,
    required this.eventType,
    this.currency = '₹',
    this.description = '',
    required this.createdAt,
    this.isArchived = false,
    this.status = 'active',
    this.estimatedBudget = 0.0,
    this.installmentsCount = 1,
    this.members = const [],
    this.creatorId,
    this.creatorEmail,
    this.driveFileId,
    this.shareCode,
    this.isShared = false,
    this.lastSyncedAt,
  });

  bool get isPlanning => status == 'planning';
  bool get isActive => status == 'active' && !isArchived;
  bool get isCompleted => status == 'completed' || isArchived;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'event_type': eventType,
      'currency': currency,
      'description': description,
      'created_at': createdAt.millisecondsSinceEpoch,
      'is_archived': isArchived ? 1 : 0,
      'status': status,
      'estimated_budget': estimatedBudget,
      'installments_count': installmentsCount,
      'creator_id': creatorId,
      'creator_email': creatorEmail,
      'drive_file_id': driveFileId,
      'share_code': shareCode,
      'is_shared': isShared ? 1 : 0,
      'last_synced_at': lastSyncedAt?.millisecondsSinceEpoch,
    };
  }

  factory EventModel.fromMap(Map<String, dynamic> map, {List<PersonModel> members = const []}) {
    return EventModel(
      id: map['id'] as String,
      title: map['title'] as String,
      eventType: map['event_type'] as String,
      currency: map['currency'] as String? ?? '₹',
      description: map['description'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      status: map['status'] as String? ?? 'active',
      estimatedBudget: (map['estimated_budget'] as num?)?.toDouble() ?? 0.0,
      installmentsCount: (map['installments_count'] as int?) ?? 1,
      members: members,
      creatorId: map['creator_id'] as String?,
      creatorEmail: map['creator_email'] as String?,
      driveFileId: map['drive_file_id'] as String?,
      shareCode: map['share_code'] as String?,
      isShared: (map['is_shared'] as int? ?? 0) == 1,
      lastSyncedAt: map['last_synced_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_synced_at'] as int)
          : null,
    );
  }

  EventModel copyWith({
    String? id,
    String? title,
    String? eventType,
    String? currency,
    String? description,
    DateTime? createdAt,
    bool? isArchived,
    String? status,
    double? estimatedBudget,
    int? installmentsCount,
    List<PersonModel>? members,
    String? creatorId,
    String? creatorEmail,
    String? driveFileId,
    String? shareCode,
    bool? isShared,
    DateTime? lastSyncedAt,
  }) {
    return EventModel(
      id: id ?? this.id,
      title: title ?? this.title,
      eventType: eventType ?? this.eventType,
      currency: currency ?? this.currency,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      isArchived: isArchived ?? this.isArchived,
      status: status ?? this.status,
      estimatedBudget: estimatedBudget ?? this.estimatedBudget,
      installmentsCount: installmentsCount ?? this.installmentsCount,
      members: members ?? this.members,
      creatorId: creatorId ?? this.creatorId,
      creatorEmail: creatorEmail ?? this.creatorEmail,
      driveFileId: driveFileId ?? this.driveFileId,
      shareCode: shareCode ?? this.shareCode,
      isShared: isShared ?? this.isShared,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}
