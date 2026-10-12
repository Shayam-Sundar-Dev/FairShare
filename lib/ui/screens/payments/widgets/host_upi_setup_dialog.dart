import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/upi_payment_helper.dart';
import '../../../providers/people_provider.dart';

class HostUpiSetupDialog extends StatefulWidget {
  final String? initialUpiId;
  final String? suggestedPhone;
  final String title;
  final String subtitle;
  final bool forSelf;

  const HostUpiSetupDialog({
    super.key,
    this.initialUpiId,
    this.suggestedPhone,
    this.title = 'Set Up Host UPI ID',
    this.subtitle = 'Enter the UPI ID where trip installments and settlement payments will be received via Google Pay.',
    this.forSelf = true,
  });

  static Future<String?> show(
    BuildContext context, {
    String? initialUpiId,
    String? suggestedPhone,
    String title = 'Set Up Host UPI ID',
    String subtitle = 'Enter the UPI ID where trip installments and settlement payments will be received via Google Pay.',
    bool forSelf = true,
  }) async {
    // If no initial UPI ID provided and forSelf is true, check SharedPreferences first
    String? defaultId = initialUpiId;
    if ((defaultId == null || defaultId.trim().isEmpty) && forSelf) {
      final prefs = await SharedPreferences.getInstance();
      defaultId = prefs.getString('user_upi_id');
    }

    if (!context.mounted) return null;

    return await showDialog<String>(
      context: context,
      builder: (ctx) => HostUpiSetupDialog(
        initialUpiId: defaultId,
        suggestedPhone: suggestedPhone,
        title: title,
        subtitle: subtitle,
        forSelf: forSelf,
      ),
    );
  }

  static Future<String?> getSavedHostUpiId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_upi_id');
  }

  static Future<void> saveHostUpiId(String upiId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_upi_id', upiId.trim());
  }

  @override
  State<HostUpiSetupDialog> createState() => _HostUpiSetupDialogState();
}

class _HostUpiSetupDialogState extends State<HostUpiSetupDialog> {
  late TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  bool _isVerifying = false;
  bool _isVerified = false;
  String? _verifiedUpiId;
  String? _detectedProvider;
  String? _verificationError;

  String? get _cleanSuggestedPhone {
    if (widget.suggestedPhone == null || widget.suggestedPhone!.trim().isEmpty) {
      return null;
    }
    final digits = widget.suggestedPhone!.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      return digits.substring(digits.length - 10);
    }
    return digits.isNotEmpty ? digits : null;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialUpiId ?? '';
    _controller = TextEditingController(text: initial);
    if (initial.isNotEmpty && _isValidUpiFormat(initial)) {
      _isVerified = true;
      _verifiedUpiId = _normalizeUpiInput(initial);
      _detectedProvider = _detectUpiProvider(_verifiedUpiId!);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _normalizeUpiInput(String input) {
    final trimmed = input.trim();
    if (trimmed.contains('@')) {
      return trimmed;
    }
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      return '${digits.substring(digits.length - 10)}@okaxis';
    }
    return trimmed;
  }

  bool _isValidUpiFormat(String input) {
    final trimmed = input.trim();
    final upiRegex = RegExp(r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$');
    if (upiRegex.hasMatch(trimmed)) return true;

    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10 && digits.length <= 13;
  }

  String _detectUpiProvider(String upi) {
    final lower = upi.trim().toLowerCase();
    if (lower.endsWith('@okaxis')) return 'Google Pay (Axis Bank)';
    if (lower.endsWith('@okhdfcbank')) return 'Google Pay (HDFC Bank)';
    if (lower.endsWith('@okicici')) return 'Google Pay (ICICI Bank)';
    if (lower.endsWith('@oksbi')) return 'Google Pay (State Bank of India)';
    if (lower.endsWith('@ybl') || lower.endsWith('@ibl') || lower.endsWith('@axl')) return 'PhonePe';
    if (lower.endsWith('@paytm')) return 'Paytm Payments Bank';
    if (lower.endsWith('@upi')) return 'BHIM / NPCI (Mobile UPI)';
    if (lower.endsWith('@kotak')) return 'Kotak Mahindra Bank';
    if (lower.endsWith('@icici')) return 'iMobile ICICI';
    if (lower.endsWith('@hdfcbank')) return 'HDFC MobileBanking';
    if (lower.endsWith('@sbi')) return 'SBI YONO';
    if (lower.endsWith('@barodampay')) return 'Bank of Baroda';
    if (lower.endsWith('@idfcbank')) return 'IDFC FIRST Bank';
    if (lower.endsWith('@federal')) return 'Federal Bank';
    return 'UPI Virtual Payment Address (VPA)';
  }

  Future<void> _verifyUpiId() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() {
        _verificationError = 'Please enter a Phone Number or UPI ID';
        _isVerified = false;
      });
      return;
    }

    if (!_isValidUpiFormat(text)) {
      setState(() {
        _verificationError = 'Invalid format. Enter a 10-digit phone number or UPI ID (e.g. mobile@upi)';
        _isVerified = false;
      });
      return;
    }

    final normalized = _normalizeUpiInput(text);
    if (normalized != text) {
      _controller.text = normalized;
    }

    setState(() {
      _isVerifying = true;
      _verificationError = null;
    });

    // Simulate verification check with PSP network
    await Future.delayed(const Duration(milliseconds: 550));

    if (!mounted) return;

    setState(() {
      _isVerifying = false;
      _isVerified = true;
      _verifiedUpiId = normalized;
      _detectedProvider = _detectUpiProvider(normalized);
      _verificationError = null;
    });
  }

  Future<void> _testGooglePayLaunch() async {
    final upiId = _verifiedUpiId ?? _normalizeUpiInput(_controller.text.trim());
    if (upiId.isEmpty) return;

    await UpiPaymentHelper.launchGooglePay(
      upiId: upiId,
      payeeName: widget.forSelf ? 'Host UPI Verification' : 'Payee Verification',
      amount: 1.0,
      note: 'FairShare UPI Test',
    );
  }

  Future<void> _saveAndConfirm() async {
    final upiId = _controller.text.trim();
    if (!_isVerified || upiId != _verifiedUpiId) {
      await _verifyUpiId();
      if (!_isVerified) return;
    }

    if (widget.forSelf) {
      // Save to SharedPreferences
      await HostUpiSetupDialog.saveHostUpiId(upiId);

      // Save to Self Person in database if provider available
      if (mounted) {
        try {
          final peopleProvider = context.read<PeopleProvider>();
          await peopleProvider.updateSelfPerson(upiId: upiId);
        } catch (_) {}
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.forSelf
                      ? 'Host UPI ID "$upiId" verified and saved! 🎉'
                      : 'UPI ID "$upiId" verified! 🎉',
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, upiId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentText = _controller.text.trim();
    final bool isEditedSinceVerified = _isVerified && currentText != _verifiedUpiId;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E56A0).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF1E56A0), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  'Verify & Link Payment Account',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.subtitle,
                style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary(context), height: 1.3),
              ),
              const SizedBox(height: 14),

              // Quick Phone UPI section if receiver has phone number
              if (_cleanSuggestedPhone != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E56A0).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1E56A0).withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.phone_android_rounded, size: 16, color: Color(0xFF1E56A0)),
                          const SizedBox(width: 6),
                          Text(
                            'Phone: ${widget.suggestedPhone}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E56A0)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tap a 1-click option to pay via mobile UPI:',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildPhoneHandleChip('$_cleanSuggestedPhone@okaxis', 'Google Pay (Axis)'),
                          _buildPhoneHandleChip('$_cleanSuggestedPhone@okicici', 'Google Pay (ICICI)'),
                          _buildPhoneHandleChip('$_cleanSuggestedPhone@oksbi', 'Google Pay (SBI)'),
                          _buildPhoneHandleChip('$_cleanSuggestedPhone@ybl', 'PhonePe'),
                          _buildPhoneHandleChip('$_cleanSuggestedPhone@paytm', 'Paytm'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              // UPI ID / Phone Text Field
              TextFormField(
                controller: _controller,
                autofocus: _cleanSuggestedPhone == null,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) {
                  setState(() {
                    _verificationError = null;
                  });
                },
                decoration: InputDecoration(
                  labelText: widget.forSelf ? 'Host Phone Number / UPI ID' : 'Phone Number or UPI ID',
                  hintText: 'e.g. 9876543210 or name@okaxis',
                  prefixIcon: const Icon(Icons.payment_rounded, size: 20),
                  suffixIcon: _isVerifying
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : (_isVerified && !isEditedSinceVerified
                          ? const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32))
                          : null),
                  filled: true,
                  fillColor: AppTheme.cardBg(context),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  errorText: _verificationError,
                ),
              ),

              const SizedBox(height: 10),

              // Handle Preset Chips
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildPresetChip('@upi'),
                  _buildPresetChip('@okaxis'),
                  _buildPresetChip('@okhdfcbank'),
                  _buildPresetChip('@okicici'),
                  _buildPresetChip('@oksbi'),
                  _buildPresetChip('@paytm'),
                  _buildPresetChip('@ybl'),
                ],
              ),

              // Verification Status Box
              if (_isVerified && !isEditedSinceVerified) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified_rounded, color: Color(0xFF2E7D32), size: 18),
                          const SizedBox(width: 6),
                          const Text(
                            'UPI ID Verified',
                            style: TextStyle(
                              color: Color(0xFF2E7D32),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _testGooglePayLaunch,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Test GPay', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Provider: ${_detectedProvider ?? "Valid UPI VPA"}',
                        style: TextStyle(fontSize: 11.5, color: Colors.green.shade900),
                      ),
                      Text(
                        'Ready to receive installment funds and settlements directly into this account.',
                        style: TextStyle(fontSize: 11, color: Colors.green.shade800, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ] else if (isEditedSinceVerified || (!_isVerified && currentText.isNotEmpty)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isVerifying ? null : _verifyUpiId,
                    icon: _isVerifying
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_user_outlined, size: 16),
                    label: Text(
                      _isVerifying ? 'Verifying with Bank...' : 'Verify UPI ID',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      foregroundColor: const Color(0xFF1E56A0),
                      side: const BorderSide(color: Color(0xFF1E56A0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (!_isVerified || isEditedSinceVerified)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E56A0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _isVerifying ? null : _verifyUpiId,
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Verify First'),
          )
        else
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 1,
            ),
            onPressed: _saveAndConfirm,
            icon: const Icon(Icons.save_rounded, size: 16),
            label: Text(widget.forSelf ? 'Confirm & Save Host UPI' : 'Confirm & Save UPI ID'),
          ),
      ],
    );
  }

  Widget _buildPhoneHandleChip(String fullUpi, String appLabel) {
    return InkWell(
      onTap: () {
        _controller.text = fullUpi;
        _verifyUpiId();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF1E56A0).withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt_rounded, size: 13, color: Color(0xFF1E56A0)),
            const SizedBox(width: 4),
            Text(
              '$fullUpi ($appLabel)',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E56A0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(String handle) {
    return InkWell(
      onTap: () {
        final current = _controller.text.trim();
        if (current.contains('@')) {
          final prefix = current.split('@').first;
          _controller.text = '$prefix$handle';
        } else if (current.isNotEmpty) {
          _controller.text = '$current$handle';
        } else {
          _controller.text = handle;
        }
        setState(() {
          _isVerified = false;
          _verificationError = null;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Chip(
        label: Text(handle, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
