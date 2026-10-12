import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/services/deep_link_handler.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/avatar_helper.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/phone_helper.dart';
import '../../../../core/utils/sync_time_formatter.dart';
import '../../../../data/models/event_model.dart';
import '../../../../data/repositories/people_repository.dart';
import '../../../providers/event_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../../providers/trip_sync_provider.dart';

class TripShareSheet extends StatefulWidget {
  final EventModel event;

  const TripShareSheet({super.key, required this.event});

  static Future<void> show(BuildContext context, EventModel event) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TripShareSheet(event: event),
    );
  }

  @override
  State<TripShareSheet> createState() => _TripShareSheetState();
}

class _TripShareSheetState extends State<TripShareSheet> {
  bool _isActionLoading = false;
  String? _statusMessage;

  Future<String?> _promptPhoneNumberDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.phone_iphone_rounded, color: Color(0xFF0284C7)),
            SizedBox(width: 10),
            Text('Your Contact Number', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Trip members will identify you by your phone number and see you in their contact list.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Mobile Number',
                hintText: 'e.g. 9876543210',
                prefixIcon: const Icon(Icons.phone_rounded),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Skip'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final text = controller.text.trim();
              Navigator.pop(ctx, text.isNotEmpty ? text : null);
            },
            child: const Text('Save & Share'),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('$label copied to clipboard!'),
          ],
        ),
        backgroundColor: const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleShareToDrive(EventModel event) async {
    final peopleRepo = PeopleRepository();
    final selfPerson = await peopleRepo.getSelfPerson();
    if (!mounted) return;
    if (selfPerson != null && selfPerson.phoneNumber.trim().isEmpty) {
      final enteredPhone = await _promptPhoneNumberDialog(context);
      if (enteredPhone != null && enteredPhone.isNotEmpty) {
        await peopleRepo.updatePerson(selfPerson.copyWith(phoneNumber: enteredPhone));
      }
    }
    if (!mounted) return;

    setState(() {
      _isActionLoading = true;
      _statusMessage = 'Uploading trip to Google Drive...';
    });

    final syncProvider = context.read<TripSyncProvider>();
    final expenseProvider = context.read<ExpenseProvider>();
    final eventProvider = context.read<EventProvider>();

    final result = await syncProvider.shareTripToDrive(
      event: event,
      expenses: expenseProvider.expenses,
      settlements: expenseProvider.settlements,
      eventProvider: eventProvider,
    );

    if (mounted) {
      setState(() {
        _isActionLoading = false;
        _statusMessage = null;
      });

      if (result.success) {
        await eventProvider.loadEvents();
        await eventProvider.selectEvent(event.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Trip shared on Google Drive!',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1E56A0),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleSyncNow(EventModel event) async {
    setState(() {
      _isActionLoading = true;
      _statusMessage = 'Syncing trip with Google Drive...';
    });

    final syncProvider = context.read<TripSyncProvider>();
    final expenseProvider = context.read<ExpenseProvider>();
    final eventProvider = context.read<EventProvider>();

    // Push local state and download latest updates bidirectionally
    await syncProvider.syncTrip(event, eventProvider: eventProvider, expenseProvider: expenseProvider);

    if (mounted) {
      await expenseProvider.loadForEvent(event.id);
      if (!mounted) return;
      await eventProvider.computeFinancials(event.id);
      if (!mounted) return;
      await eventProvider.loadEvents();
      if (!mounted) return;

      setState(() {
        _isActionLoading = false;
        _statusMessage = null;
      });

      final syncError = syncProvider.errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                syncError != null ? Icons.warning_amber_rounded : Icons.sync_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  syncError != null
                      ? 'Sync warning: $syncError'
                      : 'Google Drive trip sync complete! 🎉',
                ),
              ),
            ],
          ),
          backgroundColor: syncError != null ? Colors.orange.shade800 : const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _shareDriveInvite(EventModel event, String shareCode) async {
    final driveFileId = event.driveFileId;
    final clickableJoinUrl = await DeepLinkHandler.createClickableJoinUrl(
      shareCode: shareCode,
      driveFileId: driveFileId,
    );

    final buffer = StringBuffer();
    buffer.writeln('✈️ *Join "${event.title}" on FairShare!*');
    buffer.writeln('Collaborate on expenses, view balances, and split bills seamlessly.');
    if (event.members.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('👥 *Trip Members:*');
      for (final m in event.members) {
        final ph = m.phoneNumber.isNotEmpty ? ' (${PhoneHelper.format(m.phoneNumber)})' : '';
        buffer.writeln('• ${m.name}$ph');
      }
    }
    buffer.writeln('');
    buffer.writeln('🔗 *Tap to Join Trip:*');
    buffer.writeln(clickableJoinUrl);
    buffer.writeln('');
    buffer.writeln('_Shared via FairShare_');

    SharePlus.instance.share(ShareParams(
      text: buffer.toString(),
      subject: 'Join Trip: ${event.title}',
    ));
  }

  void _shareTextSummary(EventModel event) {
    final eventProvider = context.read<EventProvider>();
    final summary = eventProvider.currentFinancialSummary;
    final proposals = eventProvider.settlementProposals;

    final buffer = StringBuffer();
    buffer.writeln('📊 *FairShare Summary: ${event.title}*');
    buffer.writeln('Category: ${event.eventType}');
    buffer.writeln('Total Spend: ${CurrencyFormatter.format(summary?.totalSpend ?? 0, symbol: event.currency)}');
    buffer.writeln('Members: ${event.members.map((m) => m.name).join(", ")}');
    buffer.writeln('-----------------------------');

    buffer.writeln('\n💰 *Member Balances:*');
    if (summary != null) {
      for (final b in summary.memberBalances) {
        final status = b.isSettled
            ? 'Settled'
            : (b.isOwed ? 'Gets back' : 'Owes');
        buffer.writeln('• ${b.person.name}: $status ${CurrencyFormatter.format(b.netBalance.abs(), symbol: event.currency)}');
      }
    }

    buffer.writeln('\n🤝 *Suggested Settlements:*');
    if (proposals.isEmpty) {
      buffer.writeln('All settled up! 🎉');
    } else {
      for (final p in proposals) {
        buffer.writeln('• ${p.from.name} pays ${p.to.name}: ${CurrencyFormatter.format(p.amount, symbol: event.currency)}');
      }
    }

    buffer.writeln('\n_Generated via FairShare App_');

    SharePlus.instance.share(ShareParams(
      text: buffer.toString(),
      subject: 'FairShare: ${event.title}',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final eventProvider = context.watch<EventProvider>();
    // Pick the most updated version of event
    final liveEvent = eventProvider.events.firstWhere(
      (e) => e.id == widget.event.id,
      orElse: () => widget.event,
    );

    final isSharedOnDrive = liveEvent.isShared ||
        (liveEvent.driveFileId != null && liveEvent.driveFileId!.isNotEmpty);
    final shareCode = liveEvent.shareCode ??
        (liveEvent.driveFileId != null && liveEvent.driveFileId!.length >= 6
            ? liveEvent.driveFileId!.substring(0, 6).toUpperCase()
            : null);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = AppTheme.cardBg(context);
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Sheet Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.share_rounded, color: primaryColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Share "${liveEvent.title}"',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Collaborate via Google Drive or send summaries',
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),

            const SizedBox(height: 20),

            if (_isActionLoading) ...[
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: primaryColor),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        _statusMessage ?? 'Processing...',
                        style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // SECTION 1: GOOGLE DRIVE TRIP SHARING & COLLABORATION (Featured)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF1E3A8A).withValues(alpha: 0.4), const Color(0xFF0F172A)]
                      : [const Color(0xFFE0F2FE), const Color(0xFFF0FDF4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSharedOnDrive
                      ? const Color(0xFF0284C7).withValues(alpha: 0.5)
                      : (isDark ? Colors.white12 : Colors.blue.shade100),
                  width: isSharedOnDrive ? 1.5 : 1,
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.add_to_drive_rounded,
                          color: Color(0xFF0284C7),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Google Drive Collaboration',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                if (isSharedOnDrive) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2E7D32),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'LIVE',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              isSharedOnDrive
                                  ? 'Synced on Google Drive • ${SyncTimeFormatter.formatSyncTime(liveEvent.lastSyncedAt)}'
                                  : 'Share trip with group members for live sync',
                              style: TextStyle(fontSize: 11, color: textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  if (isSharedOnDrive) ...[
                    // Explanatory note
                    Text(
                      'Collaborate on expenses with friends in real time. Share the Google Drive invite link so friends can join this trip directly.',
                      style: TextStyle(fontSize: 12.5, color: textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 16),

                    // Quick Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.send_rounded, size: 16),
                            label: const Text('Invite Friends', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            onPressed: _isActionLoading ? null : () => _shareDriveInvite(liveEvent, shareCode ?? ''),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0284C7),
                            side: const BorderSide(color: Color(0xFF0284C7)),
                            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.sync_rounded, size: 16),
                          label: const Text('Sync Now', style: TextStyle(fontWeight: FontWeight.bold)),
                          onPressed: _isActionLoading ? null : () => _handleSyncNow(liveEvent),
                        ),
                      ],
                    ),
                  ] else ...[
                    // Not shared yet - prompt to share
                    Text(
                      'Upload this trip to your Google Drive to generate a shareable invite link so friends can join, view expenses, and submit receipts right from their devices!',
                      style: TextStyle(fontSize: 12, color: textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.cloud_upload_rounded),
                        label: const Text(
                          'Share & Sync via Google Drive',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        onPressed: _isActionLoading ? null : () => _handleShareToDrive(liveEvent),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // SECTION: TRIP MEMBERS & IDENTIFICATION
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.contacts_rounded, size: 18, color: primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Trip Members (${liveEvent.members.length})',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Identified by phone',
                        style: TextStyle(
                          fontSize: 11,
                          color: textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...liveEvent.members.map((member) {
                    final isSelf = member.isSelf;
                    final hasPhone = member.phoneNumber.trim().isNotEmpty;
                    final formattedPhone = hasPhone
                        ? PhoneHelper.format(member.phoneNumber)
                        : 'No phone number';

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: AvatarHelper.parseColor(member.avatarColor),
                            child: Text(
                              AvatarHelper.getInitials(member.name),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        member.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isSelf) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: primaryColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'You',
                                          style: TextStyle(
                                            color: primaryColor,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (member.count > 1) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '×${member.count}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.amber,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(
                                      hasPhone ? Icons.phone_rounded : Icons.phone_disabled_rounded,
                                      size: 12,
                                      color: hasPhone ? const Color(0xFF2E7D32) : Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      formattedPhone,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: hasPhone ? textSecondary : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // SECTION 2: OTHER SHARING METHODS
            Text(
              'MORE SHARING OPTIONS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 10),

            // Option: Text Financial Breakdown
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _shareTextSummary(liveEvent);
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF2E7D32), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Share Summary & Balances',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            'Send formatted breakdown via WhatsApp or Messages',
                            style: TextStyle(fontSize: 11, color: textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Option: Copy Summary Text
            InkWell(
              onTap: () {
                final eventProvider = context.read<EventProvider>();
                final summary = eventProvider.currentFinancialSummary;
                final proposals = eventProvider.settlementProposals;

                final buffer = StringBuffer();
                buffer.writeln('📊 FairShare Summary: ${liveEvent.title}');
                buffer.writeln('Total Spend: ${CurrencyFormatter.format(summary?.totalSpend ?? 0, symbol: liveEvent.currency)}');
                if (summary != null) {
                  for (final b in summary.memberBalances) {
                    final status = b.isSettled ? 'Settled' : (b.isOwed ? 'Gets back' : 'Owes');
                    buffer.writeln('• ${b.person.name}: $status ${CurrencyFormatter.format(b.netBalance.abs(), symbol: liveEvent.currency)}');
                  }
                }
                if (proposals.isNotEmpty) {
                  buffer.writeln('\n🤝 Suggested Settlements:');
                  for (final p in proposals) {
                    buffer.writeln('• ${p.from.name} pays ${p.to.name}: ${CurrencyFormatter.format(p.amount, symbol: liveEvent.currency)}');
                  }
                }

                _copyToClipboard(buffer.toString(), 'Trip Summary');
                Navigator.pop(context);
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.copy_all_rounded, color: Color(0xFFD97706), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Copy Summary Text',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          Text(
                            'Copy complete balances to clipboard',
                            style: TextStyle(fontSize: 11, color: textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
