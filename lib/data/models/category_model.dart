import 'package:flutter/material.dart';

import '../../core/utils/icon_helper.dart';

class CategoryModel {
  final String id;
  final String name;
  final String type; // 'expense' or 'event'
  final int iconCode;
  final int? colorValue;
  final bool isDefault;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.type,
    required this.iconCode,
    this.colorValue,
    this.isDefault = false,
  });

  /// Returns the const [IconData] for this category's icon code.
  IconData get icon => IconHelper.getIcon(iconCode);

  Color get color => colorValue != null ? Color(colorValue!) : const Color(0xFF1E56A0);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'icon_code': iconCode,
      'color_value': colorValue,
      'is_default': isDefault ? 1 : 0,
    };
  }

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      iconCode: map['icon_code'] as int,
      colorValue: map['color_value'] as int?,
      isDefault: (map['is_default'] as int? ?? 0) == 1,
    );
  }

  CategoryModel copyWith({
    String? id,
    String? name,
    String? type,
    int? iconCode,
    int? colorValue,
    bool? isDefault,
  }) {
    return CategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      iconCode: iconCode ?? this.iconCode,
      colorValue: colorValue ?? this.colorValue,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
