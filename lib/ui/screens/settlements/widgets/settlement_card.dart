import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/avatar_helper.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/phone_helper.dart';
import '../../../../core/utils/upi_payment_helper.dart';
import '../../../../core/widgets/liquid_glass.dart';
import '../../../../data/models/event_model.dart';
import '../../../../domain/models/settlement_proposal.dart';
import '../../../providers/event_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../../providers/people_provider.dart';
import '../../payments/widgets/host_upi_setup_dialog.dart';
import '../../payments/widgets/upi_qr_dialog.dart';
import '../record_settlement_dialog.dart';

class SettlementCard extends StatelessWidget {
  final EventModel event;
  final SettlementProposal proposal;

  const SettlementCard({
    super.key,
    required this.event,
    required this.proposal,
  });

  Future<String?> _resolvePayeeUpi(BuildContext context, {bool forceEdit = false}) async {
    // 1. If payee already has a valid UPI ID stored on their Person record, use it
    // (If stored UPI ends with '@upi', it was an auto-fallback and likely unregistered on Google Pay)
    String? payeeUpi = proposal.to.upiId;
    if (!forceEdit && payeeUpi != null && payeeUpi.trim().isNotEmpty && !payeeUpi.endsWith('@upi')) {
      return payeeUpi.trim();
    }

    // 2. Only if the payee IS self (the host), fallback to saved host UPI ID
    if (!forceEdit && proposal.to.isSelf) {
      payeeUpi = await HostUpiSetupDialog.getSavedHostUpiId();
      if (payeeUpi != null && payeeUpi.trim().isNotEmpty && !payeeUpi.endsWith('@upi')) {
        return payeeUpi.trim();
      }
    }

    // 3. Otherwise, prompt the user for the payee's Google Pay / Phone Number UPI ID
    if (!context.mounted) return null;
    payeeUpi = await HostUpiSetupDialog.show(
      context,
      title: proposal.to.isSelf ? 'Set Your Google Pay UPI ID' : 'Pay ${proposal.to.name}',
      subtitle: proposal.to.isSelf
          ? 'Enter your Google Pay UPI ID so group members can pay you directly.'
          : 'Enter the Google Pay UPI ID of ${proposal.to.name} (e.g. name@okaxis or ${proposal.to.phoneNumber.isNotEmpty ? proposal.to.phoneNumber : "9876543210"}@okaxis).',
      suggestedPhone: proposal.to.phoneNumber,
      initialUpiId: (payeeUpi != null && !payeeUpi.endsWith('@upi'))
          ? payeeUpi
          : (proposal.to.phoneNumber.isNotEmpty ? '${PhoneHelper.last10(proposal.to.phoneNumber)}@okaxis' : null),
      forSelf: proposal.to.isSelf,
    );

    if (payeeUpi != null && payeeUpi.trim().isNotEmpty && context.mounted) {
      // Save payee's UPI ID to their profile so user isn't asked again
      try {
        final updatedPerson = proposal.to.copyWith(upiId: payeeUpi.trim());
        await context.read<PeopleProvider>().updatePerson(updatedPerson);
      } catch (_) {}
      return payeeUpi.trim();
    }

    return null;
  }

  Future<void> _handlePayViaGPay(BuildContext context) async {
    final payeeUpi = await _resolvePayeeUpi(context);
    if (payeeUpi == null || payeeUpi.isEmpty || !context.mounted) return;

    // Start payment session and wait for native Google Pay callback result
    final result = await UpiPaymentHelper.startUpiPayment(
      upiId: payeeUpi,
      payeeName: proposal.to.name,
      amount: proposal.amount,
      note: 'Settlement: ${event.title}',
    );

    if (!context.mounted) return;

    // 1. PAYMENT SUCCEEDED AUTOMATICALLY!
    if (result.isSuccess) {
      final expenseProvider = context.read<ExpenseProvider>();
      final eventProvider = context.read<EventProvider>();

      final txnId = result.params?['txnid'] ?? result.params?['approvalrefno'] ?? 'Google Pay';

      try {
        await expenseProvider.recordSettlement(
          eventId: event.id,
          payerId: proposal.from.id,
          payeeId: proposal.to.id,
          amount: proposal.amount,
          settledAt: DateTime.now(),
          note: 'Settled via Google Pay (Txn: $txnId)',
        );

        await eventProvider.computeFinancials(event.id);
        await eventProvider.loadEvents();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Payment of ${CurrencyFormatter.format(proposal.amount, symbol: event.currency)} to ${proposal.to.name} verified & recorded!',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF2E7D32),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          _openRecordDialog(context);
        }
      }
      return;
    }

    // 2. User cancelled in Google Pay
    if (result.status == 'CANCELLED') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment cancelled in Google Pay.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // 3. Status unknown, launched via fallback, or failed - prompt user with options
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.payment_rounded, color: Color(0xFF1E56A0)),
            SizedBox(width: 8),
            Text('Payment Status'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paying ${CurrencyFormatter.format(proposal.amount, symbol: event.currency)} to ${proposal.to.name} ($payeeUpi).',
            ),
            const SizedBox(height: 10),
            const Text(
              'Did your payment complete successfully in Google Pay?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'edit'),
            child: const Text('Change UPI ID', style: TextStyle(color: Colors.orange)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'qr'),
            child: const Text('Show QR'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, 'yes'),
            child: const Text('Mark Paid'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;

    if (action == 'yes') {
      _openRecordDialog(context);
    } else if (action == 'edit') {
      final newUpi = await _resolvePayeeUpi(context, forceEdit: true);
      if (newUpi != null && newUpi.isNotEmpty && context.mounted) {
        _handlePayViaGPay(context);
      }
    } else if (action == 'qr') {
      _showQrModal(context);
    }
  }


  Future<void> _handleShareOtherReminder(BuildContext context) async {
    final creditorUpi = await _resolvePayeeUpi(context);
    if (creditorUpi == null || creditorUpi.isEmpty) return;

    UpiPaymentHelper.shareSettlementRequest(
      tripTitle: event.title,
      debtorName: proposal.from.name,
      creditorName: proposal.to.name,
      amount: proposal.amount,
      creditorUpiId: creditorUpi,
      currency: event.currency,
    );
  }

  Future<void> _showQrModal(BuildContext context) async {
    final payeeUpi = await _resolvePayeeUpi(context);
    if (payeeUpi == null || payeeUpi.isEmpty || !context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => UpiQrDialog(
        upiId: payeeUpi,
        payeeName: proposal.to.name,
        amount: proposal.amount,
        currency: event.currency,
        note: 'Settlement: ${event.title}',
        onConfirmPaid: () {
          Navigator.pop(ctx);
          _openRecordDialog(context);
        },
      ),
    );
  }

  void _openRecordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => RecordSettlementDialog(
        event: event,
        proposal: proposal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDebtor = proposal.from.isSelf;
    final isCreditor = proposal.to.isSelf;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LiquidGlassContainer(
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status tag
            if (isDebtor) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF7C2D12).withValues(alpha: 0.5) : const Color(0xFFFFEDD5),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark ? const Color(0xFFEA580C).withValues(alpha: 0.4) : const Color(0xFFFDBA74),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.outbox_rounded, size: 12, color: Color(0xFFEA580C)),
                    const SizedBox(width: 4),
                    Text(
                      'You owe ${proposal.to.name}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFEA580C),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isCreditor) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF14532D).withValues(alpha: 0.5) : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark ? const Color(0xFF16A34A).withValues(alpha: 0.4) : const Color(0xFF86EFAC),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.move_to_inbox_rounded, size: 12, color: Color(0xFF16A34A)),
                    const SizedBox(width: 4),
                    Text(
                      '${proposal.from.name} owes you',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // People & Amount Flow
            Row(
              children: [
                // Debtor (From)
                Column(
                  children: [
                    CircleAvatar(
                      radius: 19,
                      backgroundColor: AvatarHelper.getColorForName(proposal.from.name),
                      child: Text(
                        AvatarHelper.getInitials(proposal.from.name),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 68,
                      child: Text(
                        isDebtor ? 'You' : proposal.from.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // Flow arrow and Amount
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        CurrencyFormatter.format(proposal.amount, symbol: event.currency),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Row(
                        children: [
                          Expanded(child: Divider(thickness: 1.2, color: AppTheme.accentColor)),
                          Icon(Icons.arrow_forward_rounded, size: 16, color: AppTheme.accentColor),
                        ],
                      ),
                      Text(
                        'pays to',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.textSecondary(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Creditor (To)
                Column(
                  children: [
                    CircleAvatar(
                      radius: 19,
                      backgroundColor: AvatarHelper.getColorForName(proposal.to.name),
                      child: Text(
                        AvatarHelper.getInitials(proposal.to.name),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 68,
                      child: Text(
                        isCreditor ? 'You' : proposal.to.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Action Buttons Row
            Row(
              children: [
                // QR Button
                IconButton.outlined(
                  onPressed: () => _showQrModal(context),
                  icon: const Icon(Icons.qr_code_rounded, size: 18),
                  tooltip: 'Show UPI QR Code',
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(8),
                    side: BorderSide(
                      color: isDark ? AppTheme.darkBorderSubtle : AppTheme.borderSubtle,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 8),

                // Main Role-Specific Action Buttons
                if (isDebtor)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _handlePayViaGPay(context),
                      icon: const Icon(Icons.bolt_rounded, size: 18, color: Colors.white),
                      label: const Text(
                        'Pay',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E56A0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 1,
                      ),
                    ),
                  )
                else if (isCreditor)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _openRecordDialog(context),
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 16, color: Colors.white),
                      label: const Text(
                        'Received',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 1,
                      ),
                    ),
                  )
                else ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _handleShareOtherReminder(context),
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text(
                        'Share Reminder',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _openRecordDialog(context),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    child: const Text('Received'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
