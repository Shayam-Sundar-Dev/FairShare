import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/phone_helper.dart';
import '../../../../data/repositories/people_repository.dart';
import '../../../../data/services/auth_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/people_provider.dart';
import '../../payments/widgets/host_upi_setup_dialog.dart';

/// Modal dialog that prompts the user for their mandatory phone number
/// and optional UPI ID. Used on permission grant and after Google Sign-In.
class UserContactSetupDialog extends StatefulWidget {
  final String? initialPhone;
  final String? initialUpi;
  final String title;
  final String subtitle;

  const UserContactSetupDialog({
    super.key,
    this.initialPhone,
    this.initialUpi,
    this.title = 'Set Up Contact Details',
    this.subtitle = 'Please enter your mobile number and optional UPI ID to identify you in shared trips and receive payments.',
  });

  /// Displays the setup dialog. Returns true once saved.
  static Future<bool> show(
    BuildContext context, {
    String? initialPhone,
    String? initialUpi,
    String title = 'Set Up Contact Details',
    String subtitle = 'Please enter your mobile number and optional UPI ID to identify you in shared trips and receive payments.',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: UserContactSetupDialog(
          initialPhone: initialPhone,
          initialUpi: initialUpi,
          title: title,
          subtitle: subtitle,
        ),
      ),
    );
    return result ?? false;
  }

  @override
  State<UserContactSetupDialog> createState() => _UserContactSetupDialogState();
}

class _UserContactSetupDialogState extends State<UserContactSetupDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _phoneController;
  late TextEditingController _upiController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.initialPhone ?? '');
    _upiController = TextEditingController(text: widget.initialUpi ?? '');
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _upiController.dispose();
    super.dispose();
  }

  String _normalizeUpi(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.contains('@')) return trimmed;
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      return '${digits.substring(digits.length - 10)}@okaxis';
    }
    return trimmed;
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final rawPhone = _phoneController.text.trim();
      final cleanPhone = PhoneHelper.clean(rawPhone);
      final rawUpi = _upiController.text.trim();
      final normalizedUpi = rawUpi.isNotEmpty ? _normalizeUpi(rawUpi) : null;

      final peopleProvider = context.read<PeopleProvider>();
      final authService = AuthService();

      // Update Self Person in local database & people provider
      await peopleProvider.updateSelfPerson(
        phoneNumber: cleanPhone,
        upiId: normalizedUpi,
      );

      // Update phone number in AuthService preferences & current user
      await authService.updatePhoneNumber(cleanPhone);

      // Save UPI ID in preferences if provided
      if (normalizedUpi != null && normalizedUpi.isNotEmpty) {
        await HostUpiSetupDialog.saveHostUpiId(normalizedUpi);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('UserContactSetupDialog error saving: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save profile: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = AppTheme.cardBg(context);
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final borderColor = AppTheme.border(context);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Dialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: borderColor, width: 1.2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Icon and Titles
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.contact_phone_rounded,
                      color: primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Phone mandatory • UPI optional',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0284C7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              Text(
                widget.subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // MANDATORY Phone Number Field
              Text(
                'Phone Number *',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'e.g. 98765 43210',
                  hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.6)),
                  prefixIcon: Icon(Icons.phone_android_rounded, color: primaryColor, size: 20),
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: primaryColor, width: 1.8),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                ),
                validator: (val) {
                  final text = val?.trim() ?? '';
                  if (text.isEmpty) {
                    return 'Mobile number is mandatory';
                  }
                  final clean = PhoneHelper.clean(text);
                  if (clean.length < 10) {
                    return 'Please enter a valid 10-digit mobile number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Used by friends to identify you in shared trips and contacts.',
                style: TextStyle(fontSize: 11, color: textSecondary),
              ),
              const SizedBox(height: 18),

              // OPTIONAL UPI ID Field
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'UPI ID (Optional)',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Optional',
                      style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _upiController,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'e.g. yourname@okaxis or 9876543210@upi',
                  hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.6)),
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined, color: const Color(0xFF10B981), size: 20),
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.8),
                  ),
                ),
                validator: (val) {
                  final text = val?.trim() ?? '';
                  if (text.isEmpty) return null; // Optional
                  if (!text.contains('@')) {
                    final digits = text.replaceAll(RegExp(r'\D'), '');
                    if (digits.length < 10) {
                      return 'Enter a valid UPI ID (e.g. name@upi or 10-digit number)';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Receive direct payments and trip settlements via Google Pay / UPI.',
                style: TextStyle(fontSize: 11, color: textSecondary),
              ),
              const SizedBox(height: 24),

              // Save & Continue Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Save & Continue',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper to ensure the user has configured contact details (phone mandatory, UPI optional).
class UserContactSetupHelper {
  /// Prompts for contact details if phone number is missing, or forces the prompt if [forcePrompt] is true.
  static Future<bool> ensureContactDetails(
    BuildContext context, {
    bool forcePrompt = false,
    String? title,
    String? subtitle,
  }) async {
    final peopleProvider = context.read<PeopleProvider>();
    final authProvider = context.read<AuthProvider>();

    final selfPerson = peopleProvider.selfPerson ?? await PeopleRepository().getSelfPerson();
    final authPhone = authProvider.currentUser?.phoneNumber;
    final prefs = await SharedPreferences.getInstance();
    final prefsPhone = prefs.getString('user_phone_number');

    final existingPhone = (selfPerson?.phoneNumber.isNotEmpty == true)
        ? selfPerson!.phoneNumber
        : (authPhone?.isNotEmpty == true ? authPhone! : (prefsPhone ?? ''));

    final existingUpi = selfPerson?.upiId ?? prefs.getString('user_upi_id');

    // If not forced and already has a valid phone number (at least 10 digits), no need to block
    if (!forcePrompt && PhoneHelper.clean(existingPhone).length >= 10) {
      return true;
    }

    if (!context.mounted) return false;

    return await UserContactSetupDialog.show(
      context,
      initialPhone: existingPhone,
      initialUpi: existingUpi,
      title: title ?? 'Set Up Contact Details',
      subtitle: subtitle ??
          'Please enter your mobile number and optional UPI ID to identify you in shared trips and receive payments.',
    );
  }
}
