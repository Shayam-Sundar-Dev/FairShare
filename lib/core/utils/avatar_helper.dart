import 'package:flutter/material.dart';

class AvatarHelper {
  static const List<Color> avatarColors = [
    Color(0xFFE63946),
    Color(0xFF457B9D),
    Color(0xFF1D3557),
    Color(0xFF2A9D8F),
    Color(0xFFE76F51),
    Color(0xFF6D597A),
    Color(0xFFB56576),
    Color(0xFF355070),
    Color(0xFF3D5A80),
    Color(0xFF9B5DE5),
    Color(0xFFF15BB5),
    Color(0xFF00BBF9),
    Color(0xFF00F5D4),
  ];

  static Color getColorForName(String name) {
    if (name.isEmpty) return avatarColors.first;
    int hash = 0;
    for (int i = 0; i < name.length; i++) {
      hash = name.codeUnitAt(i) + ((hash << 5) - hash);
    }
    final index = hash.abs() % avatarColors.length;
    return avatarColors[index];
  }

  static String getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  static Color parseColor(String? colorHex) {
    if (colorHex == null || colorHex.trim().isEmpty) return avatarColors.first;
    try {
      String hex = colorHex.trim().replaceFirst('#', '');
      if (hex.startsWith('0x') || hex.startsWith('0X')) {
        hex = hex.substring(2);
      }
      if (hex.length == 6) {
        hex = 'FF$hex';
      }
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return avatarColors.first;
    }
  }
}
