import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/services/deep_link_handler.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/avatar_helper.dart';
import '../../../../data/models/event_model.dart';
import '../../../providers/event_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../../providers/trip_sync_provider.dart';

class ShareTripSheet extends StatefulWidget {
  final EventModel event;

  const ShareTripSheet({super.key, required this.event});

  @override
  State<ShareTripSheet> createState() => _ShareTripSheetState();
}

class _ShareTripSheetState extends State<ShareTripSheet> {
  bool _isSharingDrive = false;
  String? _shareCode;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _shareCode = widget.event.shareCode;
  }

  Future<void> _shareToDrive() async {
    setState(() {
      _isSharingDrive = true;
      _errorMessage = null;
    });

    final syncProvider = context.read<TripSyncProvider>();
    final expenseProvider = context.read<ExpenseProvider>();
    final eventProvider = context.read<EventProvider>();

    final result = await syncProvider.shareTripToDrive(
      event: widget.event,
      expenses: expenseProvider.expenses,
      settlements: expenseProvider.settlements,
      eventProvider: eventProvider,
    );

    if (mounted) {
      setState(() {
        _isSharingDrive = false;
        if (result.success) {
          _shareCode = result.shareCode;
        } else {
          _errorMessage = result.message;
        }
      });

      if (result.success) {
        await eventProvider.selectEvent(widget.event.id);
        await eventProvider.loadEvents();
      }
    }
  }

  Future<void> _shareViaSystem(String code) async {
    final driveFileId = widget.event.driveFileId;
    final clickableJoinUrl = await DeepLinkHandler.createClickableJoinUrl(
      shareCode: code,
      driveFileId: driveFileId,
    );

    final buffer = StringBuffer();
    buffer.writeln('✈️ *Join "${widget.event.title}" on FairShare!*');
    buffer.writeln('Collaborate on expenses, view balances, and split bills seamlessly.');
    buffer.writeln('');
    buffer.writeln('🔗 *Tap to Join Trip:*');
    buffer.writeln(clickableJoinUrl);
    buffer.writeln('');
    buffer.writeln('_Shared via FairShare_');

    SharePlus.instance.share(
      ShareParams(
        text: buffer.toString(),
        subject: 'Join "${widget.event.title}" on FairShare',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final isShared = _shareCode != null && _shareCode!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.cloud_sync_rounded, color: primaryColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share Trip with Members',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                    Text(
                      'Let friends watch and submit expenses for approval',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red.shade800, fontSize: 13),
              ),
            ),
            const SizedBox(height: 14),
          ],

          if (!isShared) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border(context)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.drive_folder_upload_rounded, size: 40, color: Color(0xFF1E56A0)),
                  const SizedBox(height: 10),
                  const Text(
                    'Create Shared Google Drive Link',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Uploads this trip to your Google Drive and creates a live collaboration link for your group.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: textSecondary),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isSharingDrive ? null : _shareToDrive,
                    icon: _isSharingDrive
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.cloud_upload_rounded),
                    label: Text(_isSharingDrive ? 'Sharing to Google Drive...' : 'Enable Trip Sharing'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Invite Friends Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _shareViaSystem(_shareCode!),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Invite Friends via Google Drive', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Members in Trip List
            Text(
              'Trip Participants (${widget.event.members.length})',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border(context)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: widget.event.members.length,
                separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.border(context)),
                itemBuilder: (ctx, i) {
                  final member = widget.event.members[i];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor: AvatarHelper.getColorForName(member.name),
                      child: Text(
                        AvatarHelper.getInitials(member.name),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      member.isSelf ? '${member.name} (Organizer)' : member.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    subtitle: member.phoneNumber.isNotEmpty
                        ? Text(member.phoneNumber, style: TextStyle(fontSize: 11, color: textSecondary))
                        : null,
                    trailing: member.count > 1
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${member.count} ppl',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: primaryColor),
                            ),
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
