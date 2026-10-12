import 'package:intl/intl.dart';

class CurrencyFormatter {
  static String format(double amount, {String symbol = '₹'}) {
    final format = NumberFormat.currency(
      symbol: symbol,
      decimalDigits: amount % 1 == 0 ? 0 : 2,
    );
    return format.format(amount);
  }

  static String formatCompact(double amount, {String symbol = '₹'}) {
    final format = NumberFormat.compactCurrency(
      symbol: symbol,
      decimalDigits: 1,
    );
    return format.format(amount);
  }
}
