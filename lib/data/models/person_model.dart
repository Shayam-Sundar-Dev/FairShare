class PersonModel {
  final String id;
  final String name;
  final String phoneNumber;
  final String? contactId;
  final String? avatarColor;
  final bool isSelf;
  final String? upiId;
  final int count;

  const PersonModel({
    required this.id,
    required this.name,
    required this.phoneNumber,
    this.contactId,
    this.avatarColor,
    this.isSelf = false,
    this.upiId,
    this.count = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone_number': phoneNumber,
      'contact_id': contactId,
      'avatar_color': avatarColor,
      'is_self': isSelf ? 1 : 0,
      'upi_id': upiId,
      'count': count,
    };
  }

  factory PersonModel.fromMap(Map<String, dynamic> map) {
    return PersonModel(
      id: map['id'] as String,
      name: map['name'] as String,
      phoneNumber: map['phone_number'] as String? ?? '',
      contactId: map['contact_id'] as String?,
      avatarColor: map['avatar_color'] as String?,
      isSelf: (map['is_self'] as int? ?? 0) == 1,
      upiId: map['upi_id'] as String?,
      count: (map['count'] as int?) ?? 1,
    );
  }

  PersonModel copyWith({
    String? id,
    String? name,
    String? phoneNumber,
    String? contactId,
    String? avatarColor,
    bool? isSelf,
    String? upiId,
    int? count,
  }) {
    return PersonModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      contactId: contactId ?? this.contactId,
      avatarColor: avatarColor ?? this.avatarColor,
      isSelf: isSelf ?? this.isSelf,
      upiId: upiId ?? this.upiId,
      count: count ?? this.count,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersonModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
