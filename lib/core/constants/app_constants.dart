import 'package:flutter/material.dart';

class EventCategories {
  static const String trip = 'Trip';
  static const String birthday = 'Birthday';
  static const String dinner = 'Dinner / Outing';
  static const String home = 'Home / Flat';
  static const String project = 'Project';
  static const String custom = 'Custom';

  static const List<String> all = [
    trip,
    birthday,
    dinner,
    home,
    project,
    custom,
  ];

  static IconData getIcon(String category) {
    switch (category) {
      case trip:
        return Icons.flight_takeoff_rounded;
      case birthday:
        return Icons.cake_rounded;
      case dinner:
        return Icons.restaurant_rounded;
      case home:
        return Icons.home_rounded;
      case project:
        return Icons.work_outline_rounded;
      case custom:
      default:
        return Icons.celebration_rounded;
    }
  }

  static Color getColor(String category) {
    switch (category) {
      case trip:
        return const Color(0xFF0077B6);
      case birthday:
        return const Color(0xFFE63946);
      case dinner:
        return const Color(0xFFF77F00);
      case home:
        return const Color(0xFF2A9D8F);
      case project:
        return const Color(0xFF6D597A);
      case custom:
      default:
        return const Color(0xFF7209B7);
    }
  }
}

class ExpenseCategories {
  static const String food = 'Food & Drinks';
  static const String travel = 'Travel & Transport';
  static const String stay = 'Accommodation';
  static const String entertainment = 'Entertainment';
  static const String shopping = 'Shopping';
  static const String bills = 'Bills & Utilities';
  static const String general = 'General';

  static const List<String> all = [
    food,
    travel,
    stay,
    entertainment,
    shopping,
    bills,
    general,
  ];

  static IconData getIcon(String category) {
    switch (category) {
      case food:
        return Icons.fastfood_rounded;
      case travel:
        return Icons.directions_car_rounded;
      case stay:
        return Icons.hotel_rounded;
      case entertainment:
        return Icons.movie_creation_rounded;
      case shopping:
        return Icons.shopping_bag_rounded;
      case bills:
        return Icons.receipt_long_rounded;
      case general:
      default:
        return Icons.payments_rounded;
    }
  }

  static Color getColor(String category) {
    switch (category) {
      case food:
        return const Color(0xFFE63946);
      case travel:
        return const Color(0xFF1D3557);
      case stay:
        return const Color(0xFF457B9D);
      case entertainment:
        return const Color(0xFF7209B7);
      case shopping:
        return const Color(0xFFF77F00);
      case bills:
        return const Color(0xFF2A9D8F);
      case general:
      default:
        return const Color(0xFF4A5568);
    }
  }
}

enum SplitType {
  equal,
  exact,
  percentage,
  shares,
}

extension SplitTypeExtension on SplitType {
  String get displayName {
    switch (this) {
      case SplitType.equal:
        return 'Equally';
      case SplitType.exact:
        return 'Exact Amounts';
      case SplitType.percentage:
        return 'By Percentage';
      case SplitType.shares:
        return 'By Shares';
    }
  }

  String get dbValue {
    switch (this) {
      case SplitType.equal:
        return 'EQUAL';
      case SplitType.exact:
        return 'EXACT';
      case SplitType.percentage:
        return 'PERCENTAGE';
      case SplitType.shares:
        return 'SHARES';
    }
  }

  static SplitType fromDbValue(String? value) {
    if (value == null) return SplitType.equal;
    switch (value.toUpperCase()) {
      case 'EXACT':
        return SplitType.exact;
      case 'PERCENTAGE':
        return SplitType.percentage;
      case 'SHARES':
        return SplitType.shares;
      case 'EQUAL':
      default:
        return SplitType.equal;
    }
  }
}

class DebugLog {
  static String lastLog = '';
}
