import 'package:flutter/material.dart';

/// Maps icon code points to their const [IconData] equivalents.
///
/// Flutter's release build tree-shakes unused icon glyphs by scanning for
/// `const IconData(...)` calls. When a code point is loaded from the database
/// at runtime, the tree shaker can't resolve it statically and the build
/// fails. This lookup table solves the problem by mapping every code point
/// the app may store back to the original `Icons.*` constant, satisfying the
/// tree shaker while keeping the DB schema unchanged.
class IconHelper {
  IconHelper._();

  /// All icons available for category selection, plus default category icons.
  ///
  /// Keys are [IconData.codePoint] values; values are the corresponding
  /// `Icons.*` constants. If a code point isn't in this map (e.g. data from
  /// a future app version), [getIcon] falls back to [Icons.category_rounded].
  static final Map<int, IconData> _iconMap = <int, IconData>{
    // ── Expense category defaults ──
    Icons.fastfood_rounded.codePoint: Icons.fastfood_rounded,
    Icons.directions_car_rounded.codePoint: Icons.directions_car_rounded,
    Icons.hotel_rounded.codePoint: Icons.hotel_rounded,
    Icons.movie_creation_rounded.codePoint: Icons.movie_creation_rounded,
    Icons.shopping_bag_rounded.codePoint: Icons.shopping_bag_rounded,
    Icons.receipt_long_rounded.codePoint: Icons.receipt_long_rounded,
    Icons.payments_rounded.codePoint: Icons.payments_rounded,

    // ── Event category defaults ──
    Icons.flight_takeoff_rounded.codePoint: Icons.flight_takeoff_rounded,
    Icons.cake_rounded.codePoint: Icons.cake_rounded,
    Icons.restaurant_rounded.codePoint: Icons.restaurant_rounded,
    Icons.home_rounded.codePoint: Icons.home_rounded,
    Icons.work_outline_rounded.codePoint: Icons.work_outline_rounded,
    Icons.celebration_rounded.codePoint: Icons.celebration_rounded,

    // ── Additional picker icons ──
    Icons.local_cafe_rounded.codePoint: Icons.local_cafe_rounded,
    Icons.local_bar_rounded.codePoint: Icons.local_bar_rounded,
    Icons.directions_bus_rounded.codePoint: Icons.directions_bus_rounded,
    Icons.train_rounded.codePoint: Icons.train_rounded,
    Icons.local_gas_station_rounded.codePoint: Icons.local_gas_station_rounded,
    Icons.sports_esports_rounded.codePoint: Icons.sports_esports_rounded,
    Icons.music_note_rounded.codePoint: Icons.music_note_rounded,
    Icons.shopping_cart_rounded.codePoint: Icons.shopping_cart_rounded,
    Icons.lightbulb_rounded.codePoint: Icons.lightbulb_rounded,
    Icons.savings_rounded.codePoint: Icons.savings_rounded,
    Icons.medical_services_rounded.codePoint: Icons.medical_services_rounded,
    Icons.fitness_center_rounded.codePoint: Icons.fitness_center_rounded,
    Icons.pets_rounded.codePoint: Icons.pets_rounded,
    Icons.card_giftcard_rounded.codePoint: Icons.card_giftcard_rounded,
    Icons.school_rounded.codePoint: Icons.school_rounded,
    Icons.build_rounded.codePoint: Icons.build_rounded,
    Icons.beach_access_rounded.codePoint: Icons.beach_access_rounded,
    Icons.camera_alt_rounded.codePoint: Icons.camera_alt_rounded,
    Icons.local_hospital_rounded.codePoint: Icons.local_hospital_rounded,

    // ── Fallback ──
    Icons.category_rounded.codePoint: Icons.category_rounded,
  };

  /// Returns the const [IconData] for the given [codePoint].
  ///
  /// Falls back to [Icons.category_rounded] if the code point is unknown.
  static IconData getIcon(int codePoint) {
    return _iconMap[codePoint] ?? Icons.category_rounded;
  }
}
