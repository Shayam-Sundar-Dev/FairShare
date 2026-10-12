class PhoneHelper {
  /// Strips all non-digit characters from the phone number
  static String clean(String? phone) {
    if (phone == null) return '';
    return phone.replaceAll(RegExp(r'\D'), '');
  }

  /// Extracts the significant 10-digit portion (or all digits if shorter)
  static String last10(String? phone) {
    final cleaned = clean(phone);
    if (cleaned.length >= 10) {
      return cleaned.substring(cleaned.length - 10);
    }
    return cleaned;
  }

  /// Determines if two phone numbers identify the same contact
  static bool isSamePhone(String? phone1, String? phone2) {
    if (phone1 == null || phone2 == null) return false;
    final c1 = clean(phone1);
    final c2 = clean(phone2);
    if (c1.isEmpty || c2.isEmpty) return false;
    if (c1 == c2) return true;
    if (c1.length >= 10 && c2.length >= 10) {
      return last10(c1) == last10(c2);
    }
    return false;
  }

  /// Formats a phone number for clean, uniform display
  static String format(String? phone) {
    if (phone == null || phone.trim().isEmpty) return '';
    final trimmed = phone.trim();
    final cleaned = clean(trimmed);
    if (cleaned.length == 10) {
      return '${cleaned.substring(0, 5)} ${cleaned.substring(5)}';
    } else if (cleaned.length == 12 && cleaned.startsWith('91')) {
      return '+91 ${cleaned.substring(2, 7)} ${cleaned.substring(7)}';
    }
    return trimmed;
  }

  /// Extracts a 10-digit phone number from a UPI ID (e.g. 7418373273@okicici -> 7418373273)
  static String extractPhoneFromUpi(String? upi) {
    if (upi == null || !upi.contains('@')) return '';
    final handle = upi.split('@').first;
    final cleaned = clean(handle);
    if (cleaned.length == 10) return cleaned;
    if (cleaned.length == 12 && cleaned.startsWith('91')) return last10(cleaned);
    return '';
  }
}
