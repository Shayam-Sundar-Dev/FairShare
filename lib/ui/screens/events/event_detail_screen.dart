import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/deep_link_handler.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/avatar_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/phone_helper.dart';
import '../../../core/utils/upi_payment_helper.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../data/models/event_model.dart';
import '../../../data/models/expense_model.dart';
import '../../../data/models/person_model.dart';
import '../../../data/models/trip_installment_model.dart';
import '../../../domain/algorithms/installment_calculator.dart';
import '../../../domain/models/settlement_proposal.dart';
import '../../providers/category_provider.dart';
import '../../providers/event_provider.dart';
import '../../providers/expense_provider.dart';
import '../../providers/trip_sync_provider.dart';
import '../expenses/add_expense_screen.dart';
import '../payments/widgets/host_upi_setup_dialog.dart';
import '../payments/widgets/upi_qr_dialog.dart';
import '../settlements/record_settlement_dialog.dart';
import '../settlements/widgets/settlement_card.dart';
import 'add_event_screen.dart';

class EventDetailScreen extends StatefulWidget {
  final String eventId;

  const EventDetailScreen({super.key, required this.eventId});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;
  int _currentTabCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  void _updateTabController(int count) {
    if (_tabController == null || _currentTabCount != count) {
      final oldIndex = _tabController?.index ?? 0;
      _tabController?.removeListener(_handleTabChange);
      _tabController?.dispose();
      _currentTabCount = count;
      _tabController = TabController(
        length: count,
        vsync: this,
        initialIndex: oldIndex < count ? oldIndex : 0,
      );
      _tabController!.addListener(_handleTabChange);
    }
  }

  void _handleTabChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabChange);
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool syncWithDrive = true}) async {
    final eventProvider = context.read<EventProvider>();
    final expenseProvider = context.read<ExpenseProvider>();
    final tripSyncProvider = context.read<TripSyncProvider>();

    await eventProvider.selectEvent(widget.eventId);
    await expenseProvider.loadForEvent(widget.eventId);
    await eventProvider.computeFinancials(widget.eventId);
    await eventProvider.loadTripInstallments(widget.eventId);
    if (mounted) setState(() {});

    final event = eventProvider.selectedEvent;

    // If trip is shared on Google Drive, proactively sync in background without freezing UI
    if (syncWithDrive && event != null && (event.isShared || (event.driveFileId != null && event.driveFileId!.isNotEmpty))) {
      if (!tripSyncProvider.isSyncing) {
        tripSyncProvider.syncTrip(event, eventProvider: eventProvider, expenseProvider: expenseProvider).then((_) async {
          if (mounted) {
            await expenseProvider.loadForEvent(widget.eventId);
            await eventProvider.computeFinancials(widget.eventId);
            setState(() {});
          }
        }).catchError((e) {
          debugPrint('Error proactively syncing trip: $e');
        });
      }
    }
  }

  Future<bool> _confirmDeleteExpense(ExpenseModel expense, EventModel event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Expense'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${expense.title}" (${CurrencyFormatter.format(expense.amount, symbol: event.currency)})?\n\nThis will recalculate all group balances.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.negativeRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final expenseProvider = context.read<ExpenseProvider>();
        final eventProvider = context.read<EventProvider>();
        final tripSyncProvider = context.read<TripSyncProvider>();

        await expenseProvider.deleteExpense(expense.id, event.id);
        await eventProvider.computeFinancials(event.id);
        await eventProvider.refreshEventInList(event.id);

        await _loadData(syncWithDrive: false);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Expense "${expense.title}" deleted'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 2),
            ),
          );
        }

        if (event.isShared || (event.driveFileId != null && event.driveFileId!.isNotEmpty)) {
          tripSyncProvider.syncTrip(
            event,
            eventProvider: eventProvider,
            expenseProvider: expenseProvider,
          ).catchError((e) {
            debugPrint('Error syncing after delete: $e');
          });
        }
        return true;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete expense: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }
    }
    return false;
  }

  // --- Google Pay / UPI Installment Handlers ---

  Future<String?> _resolveHostUpiId(EventModel event) async {
    final host = event.members.firstWhere(
      (m) => m.isSelf,
      orElse: () => event.members.first,
    );

    if (host.upiId != null && host.upiId!.trim().isNotEmpty) {
      return host.upiId!.trim();
    }

    // Check SharedPreferences fallback
    final saved = await HostUpiSetupDialog.getSavedHostUpiId();
    if (saved != null && saved.trim().isNotEmpty) {
      return saved.trim();
    }

    // Prompt user to set up Host UPI ID
    if (!mounted) return null;
    return await HostUpiSetupDialog.show(
      context,
      title: 'Set Up Host UPI ID',
      subtitle: 'Enter the UPI ID where trip installments will be received via Google Pay.',
    );
  }

  Future<void> _shareTripInvite(BuildContext context, EventModel event) async {
    final tripSyncProvider = context.read<TripSyncProvider>();
    final eventProvider = context.read<EventProvider>();

    String? driveFileId = event.driveFileId;

    if (driveFileId == null || driveFileId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 12),
                Text('Preparing trip invite link...'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final result = await tripSyncProvider.shareTripToDrive(
        event: event,
        eventProvider: eventProvider,
      );
      if (result.success && result.driveFileId != null) {
        driveFileId = result.driveFileId;
        await eventProvider.refreshEventInList(event.id);
      }
    }

    final shareCode = event.shareCode ?? event.id.substring(0, min(6, event.id.length)).toUpperCase();
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

    await SharePlus.instance.share(ShareParams(
      text: buffer.toString(),
      subject: 'Join Trip: ${event.title}',
    ));
  }

  Future<void> _shareInstallmentRequest(
    EventModel event,
    InstallmentMilestone milestone,
  ) async {
    final hostUpi = await _resolveHostUpiId(event);
    if (hostUpi == null || hostUpi.trim().isEmpty) return;

    final host = event.members.firstWhere(
      (m) => m.isSelf,
      orElse: () => event.members.first,
    );

    final unpaidMembers = milestone.memberInstallments
        .where((i) => !i.isPaid)
        .map((i) {
          final m = event.members.cast<PersonModel?>().firstWhere(
                (p) => p?.id == i.personId,
                orElse: () => null,
              );
          return m?.name ?? 'Member';
        })
        .toList();

    UpiPaymentHelper.shareInstallmentRequest(
      tripTitle: event.title,
      installmentNumber: milestone.installmentNumber,
      amount: milestone.expectedPerShare,
      hostName: host.name,
      hostUpiId: hostUpi,
      currency: event.currency,
      memberNames: unpaidMembers,
    );
  }

  Future<void> _showInstallmentQrDialog(
    EventModel event,
    InstallmentMilestone milestone,
  ) async {
    final hostUpi = await _resolveHostUpiId(event);
    if (hostUpi == null || hostUpi.trim().isEmpty || !mounted) return;

    final host = event.members.firstWhere(
      (m) => m.isSelf,
      orElse: () => event.members.first,
    );

    showDialog(
      context: context,
      builder: (ctx) => UpiQrDialog(
        upiId: hostUpi,
        payeeName: host.name,
        amount: milestone.expectedPerShare,
        currency: event.currency,
        note: '${event.title} - Installment #${milestone.installmentNumber}',
        title: 'Installment #${milestone.installmentNumber} QR',
      ),
    );
  }

  Future<void> _payInstallmentViaGPay(
    EventModel event,
    TripInstallmentModel installment,
  ) async {
    final hostUpi = await _resolveHostUpiId(event);
    if (hostUpi == null || hostUpi.trim().isEmpty || !mounted) return;

    final host = event.members.firstWhere(
      (m) => m.isSelf,
      orElse: () => event.members.first,
    );

    final success = await UpiPaymentHelper.launchGooglePay(
      upiId: hostUpi,
      payeeName: host.name,
      amount: installment.expectedAmount,
      note: '${event.title} - Installment #${installment.installmentNumber}',
    );

    if (!mounted) return;

    if (!success) {
      // Fallback to QR Dialog
      showDialog(
        context: context,
        builder: (ctx) => UpiQrDialog(
          upiId: hostUpi,
          payeeName: host.name,
          amount: installment.expectedAmount,
          currency: event.currency,
          note: '${event.title} - Installment #${installment.installmentNumber}',
          title: 'Pay Installment via UPI',
          onConfirmPaid: () async {
            Navigator.pop(ctx);
            await context.read<EventProvider>().toggleInstallmentPaid(installment);
            _loadData();
          },
        ),
      );
      return;
    }

    // Returning from Google Pay: Confirm and mark as paid
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: Color(0xFF2E7D32)),
            SizedBox(width: 8),
            Text('Payment Successful?'),
          ],
        ),
        content: Text(
          'Did your Google Pay payment of ${CurrencyFormatter.format(installment.expectedAmount, symbol: event.currency)} for Installment #${installment.installmentNumber} complete successfully?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not Yet'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Mark as Paid'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final eventProvider = context.read<EventProvider>();
      await eventProvider.toggleInstallmentPaid(installment);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🎉 Installment #${installment.installmentNumber} marked as Paid! Added to Committee Pool.',
            ),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventProvider = context.watch<EventProvider>();
    final expenseProvider = context.watch<ExpenseProvider>();
    final tripSyncProvider = context.watch<TripSyncProvider>();
    final event = eventProvider.selectedEvent;

    if (eventProvider.isLoading || event == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading Event...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final hasPlanTab = event.isPlanning ||
        event.estimatedBudget > 0 ||
        eventProvider.installments.isNotEmpty;
    final tabCount = hasPlanTab ? 4 : 3;
    final expenseTabIndex = hasPlanTab ? 1 : 0;

    final categoryProvider = context.watch<CategoryProvider>();
    final catColor = categoryProvider.getEventColor(event.eventType);
    final catIcon = categoryProvider.getEventIcon(event.eventType);
    final financialSummary = eventProvider.currentFinancialSummary;
    final proposals = eventProvider.settlementProposals;
    final expenses = expenseProvider.expenses;
    final settlements = expenseProvider.settlements;
    final planSummary = eventProvider.installmentPlanSummary;

    _updateTabController(tabCount);
    final isExpensesTab = (_tabController?.index ?? 0) == expenseTabIndex;

    return Scaffold(
      appBar: AppBar(
        title: Text(event.title),
        actions: [
          if (event.isArchived)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF2E7D32)),
                  SizedBox(width: 4),
                  Text(
                    'History',
                    style: TextStyle(
                      color: Color(0xFF2E7D32),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          else if (proposals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.task_alt_rounded, size: 16),
                label: const Text(
                  'Split Complete',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _confirmCompleteSplit(context, event),
              ),
            ),
          IconButton(
            icon: tripSyncProvider.isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.sync_rounded),
            tooltip: 'Sync with Google Drive',
            onPressed: tripSyncProvider.isSyncing
                ? null
                : () async {
                    if (event.driveFileId == null || event.driveFileId!.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              ),
                              SizedBox(width: 12),
                              Text('Uploading trip to Google Drive...'),
                            ],
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                      final result = await tripSyncProvider.shareTripToDrive(
                        event: event,
                        eventProvider: eventProvider,
                      );
                      if (result.success && context.mounted) {
                        await eventProvider.refreshEventInList(event.id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Trip connected to Google Drive!'),
                            backgroundColor: Color(0xFF2E7D32),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                            SizedBox(width: 12),
                            Text('Syncing with Google Drive...'),
                          ],
                        ),
                        duration: Duration(seconds: 1),
                      ),
                    );
                    await tripSyncProvider.syncTrip(
                      event,
                      eventProvider: eventProvider,
                      expenseProvider: expenseProvider,
                    );
                    if (context.mounted) {
                      await expenseProvider.loadForEvent(event.id);
                      await eventProvider.computeFinancials(event.id);
                      if (!context.mounted) return;
                      final errMsg = tripSyncProvider.errorMessage;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            errMsg != null && errMsg.isNotEmpty
                                ? 'Sync error: $errMsg'
                                : 'Sync complete!',
                          ),
                          backgroundColor: errMsg != null && errMsg.isNotEmpty
                              ? Colors.red
                              : const Color(0xFF2E7D32),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Share Invite Link',
            onPressed: () => _shareTripInvite(context, event),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Event',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => AddEventScreen(existingEvent: event),
                ),
              );
              _loadData();
            },
          ),
        ],
      ),
      floatingActionButton: isExpensesTab
          ? Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: FloatingActionButton.extended(
                elevation: 2,
                highlightElevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                onPressed: () async {
                  final added = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (ctx) => AddExpenseScreen(event: event),
                    ),
                  );
                  if (added == true && mounted) {
                    _loadData(syncWithDrive: false);
                  }
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Expense', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return [
              SliverToBoxAdapter(
                child: _buildHeaderCard(context, event, catColor, catIcon, financialSummary),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverAppBarDelegate(
                  TabBar(
                    controller: _tabController,
                    isScrollable: hasPlanTab,
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: UnderlineTabIndicator(
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3.0,
                      ),
                      borderRadius: BorderRadius.circular(3),
                      insets: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    labelColor: Theme.of(context).colorScheme.primary,
                    unselectedLabelColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: -0.2),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, letterSpacing: -0.2),
                    tabs: [
                      if (hasPlanTab)
                        Tab(
                          text: 'Plan & Pool (${event.installmentsCount})',
                          icon: const Icon(Icons.savings_rounded, size: 20),
                        ),
                      Tab(
                        text: 'Expenses (${expenses.length})',
                        icon: const Icon(Icons.receipt_long_rounded, size: 20),
                      ),
                      Tab(
                        text: 'Balances (${event.members.length})',
                        icon: const Icon(Icons.account_balance_wallet_rounded, size: 20),
                      ),
                      Tab(
                        text: 'Settle Up (${proposals.length})',
                        icon: const Icon(Icons.handshake_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              if (hasPlanTab)
                _buildPlanTab(context, event, eventProvider, planSummary),

              // Expenses
              _buildExpensesTab(context, event, expenses),

              // Balances
              _buildBalancesTab(context, event, financialSummary),

              // Settle Up
              _buildSettleUpTab(context, event, proposals, settlements),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    BuildContext context,
    EventModel event,
    Color catColor,
    IconData catIcon,
    dynamic financialSummary,
  ) {
    final totalSpend = financialSummary?.totalSpend ?? 0.0;
    final totalMembersShares = event.members.fold<int>(
      0,
      (sum, m) => sum + max(1, m.count),
    );
    final perPersonSpend = totalMembersShares > 0 ? totalSpend / totalMembersShares : 0.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: LiquidGlassContainer(
        borderRadius: BorderRadius.circular(16),
        borderWidth: 0.9,
        blur: 12,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (event.isArchived) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF14532D) : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? const Color(0xFF15803D) : Colors.green.shade200,
                    width: 0.9,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Split Completed • Saved in History',
                        style: TextStyle(
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _confirmReopenEvent(context, event),
                      child: const Text(
                        'Reopen',
                        style: TextStyle(
                          color: Color(0xFF1E56A0),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: isDark ? 0.16 : 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: catColor.withValues(alpha: isDark ? 0.3 : 0.15),
                      width: 0.9,
                    ),
                  ),
                  child: Icon(catIcon, color: catColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        event.isPlanning
                            ? 'Planning Mode • ${event.eventType}'
                            : event.eventType,
                        style: TextStyle(color: catColor, fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      CurrencyFormatter.format(totalSpend, symbol: event.currency),
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: primaryColor,
                      ),
                    ),
                    Text(
                      'Total Spend',
                      style: TextStyle(fontSize: 10.5, color: textSecondary),
                    ),
                    if (event.members.isNotEmpty)
                      Text(
                        '${CurrencyFormatter.format(perPersonSpend, symbol: event.currency)} / person',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: textSecondary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (event.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  event.description,
                  style: TextStyle(fontSize: 12.5, color: textSecondary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- Plan & Committee Pool Tab ---

  Widget _buildPlanTab(
    BuildContext context,
    EventModel event,
    EventProvider eventProvider,
    InstallmentPlanSummary? planSummary,
  ) {
    final poolBalance = eventProvider.committeePoolBalance;
    final totalPoolCollected = eventProvider.totalCommitteeFundPaid;
    final totalBudget = event.estimatedBudget > 0
        ? event.estimatedBudget
        : (planSummary?.totalBudget ?? 0.0);
    final progress = totalBudget > 0 ? (totalPoolCollected / totalBudget).clamp(0.0, 1.0) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Committee Fund & Budget Overview Card
          LiquidGlassContainer(
            borderRadius: BorderRadius.circular(18),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00A896).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.savings_rounded, color: Color(0xFF00A896), size: 22),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Trip Committee Fund',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              event.isPlanning
                                  ? 'Collecting installment payments'
                                  : 'Active pool for trip spending',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: event.isPlanning
                            ? Colors.amber.shade100
                            : Colors.green.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        event.isPlanning ? 'Planning ⏳' : 'Active 🏖️',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: event.isPlanning
                              ? Colors.amber.shade900
                              : const Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Pool Fund Metrics
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.cardBg(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border(context)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Pool Collected', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text(
                              CurrencyFormatter.format(totalPoolCollected, symbol: event.currency),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00A896),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.cardBg(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border(context)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.isPlanning ? 'Target Budget' : 'Remaining Pool',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              CurrencyFormatter.format(
                                event.isPlanning ? totalBudget : poolBalance,
                                symbol: event.currency,
                              ),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Progress Bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}% of budget collected',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${CurrencyFormatter.format(totalPoolCollected, symbol: event.currency)} / ${CurrencyFormatter.format(totalBudget, symbol: event.currency)}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00A896)),
                      ),
                    ),
                  ],
                ),

                // Host UPI ID info bar
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E56A0).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_rounded, size: 16, color: Color(0xFF1E56A0)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'GPay & UPI requests will route to Host account',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF1E56A0), fontWeight: FontWeight.w500),
                        ),
                      ),
                      TextButton(
                        onPressed: () => HostUpiSetupDialog.show(context),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(50, 24),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Edit UPI ID', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),

                // "Start Trip" action button for planning phase
                if (event.isPlanning) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 1,
                      ),
                      icon: const Icon(Icons.flight_takeoff_rounded, size: 20),
                      label: const Text(
                        'Start Trip (Begin Spending Pool)',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () async {
                        await eventProvider.startTrip(event.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('🎉 Trip Started! Expenses will now spend from the Committee Pool.'),
                              backgroundColor: Color(0xFF2E7D32),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          _loadData();
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 2. Installment Milestones List
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Installment Milestones (${planSummary?.milestones.length ?? event.installmentsCount})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (planSummary != null)
                Text(
                  '${planSummary.completedMilestonesCount} of ${planSummary.totalInstallments} Completed',
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (planSummary != null && planSummary.milestones.isNotEmpty) ...[
            ...planSummary.milestones.map((milestone) {
              return _buildMilestoneCard(context, event, eventProvider, milestone);
            }),
          ] else
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border(context)),
              ),
              child: const Center(
                child: Text(
                  'Installment plan will appear once members and budget are configured.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMilestoneCard(
    BuildContext context,
    EventModel event,
    EventProvider eventProvider,
    InstallmentMilestone milestone,
  ) {
    final isDone = milestone.isFullyCollected;
    final paidCount = milestone.memberInstallments.where((i) => i.isPaid).length;
    final totalCount = milestone.memberInstallments.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDone ? Colors.green.shade200 : AppTheme.border(context),
          width: isDone ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Milestone Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDone
                  ? Colors.green.shade50.withValues(alpha: 0.5)
                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: isDone ? const Color(0xFF2E7D32) : Theme.of(context).colorScheme.primary,
                  child: Text(
                    '#${milestone.installmentNumber}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Installment #${milestone.installmentNumber}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        '${CurrencyFormatter.format(milestone.expectedPerShare, symbol: event.currency)} / person • Expected: ${CurrencyFormatter.format(milestone.totalExpected, symbol: event.currency)}',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDone ? Colors.green.shade100 : Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isDone ? 'Completed 🎉' : '$paidCount/$totalCount Paid',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDone ? const Color(0xFF2E7D32) : Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Milestone Actions Bar (GPay Request & QR Code)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _shareInstallmentRequest(event, milestone),
                    icon: const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF1E56A0)),
                    label: const Text(
                      'GPay Group Request',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E56A0)),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: const BorderSide(color: Color(0xFF1E56A0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: () => _showInstallmentQrDialog(event, milestone),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                  tooltip: 'Show GPay QR Code',
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(8),
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 12),

          // Member Installments Breakdown
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            itemCount: milestone.memberInstallments.length,
            separatorBuilder: (_, _) => const Divider(height: 10, indent: 44),
            itemBuilder: (context, idx) {
              final inst = milestone.memberInstallments[idx];
              final member = event.members.cast<PersonModel?>().firstWhere(
                    (m) => m?.id == inst.personId,
                    orElse: () => null,
                  );
              final memberName = member != null ? (member.isSelf ? '${member.name} (You)' : member.name) : 'Member';
              final isSelf = member?.isSelf ?? false;

              return Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: AvatarHelper.getColorForName(memberName),
                    child: Text(
                      AvatarHelper.getInitials(memberName),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          memberName,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: isSelf ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                        if ((member?.count ?? 1) > 1)
                          Text(
                            '${member!.count} shares',
                            style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        CurrencyFormatter.format(inst.expectedAmount, symbol: event.currency),
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            inst.isPaid ? Icons.check_circle_rounded : Icons.pending_outlined,
                            size: 12,
                            color: inst.isPaid ? const Color(0xFF2E7D32) : Colors.orange,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            inst.isPaid ? 'Paid' : 'Due',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: inst.isPaid ? const Color(0xFF2E7D32) : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),

                  // Action for this member
                  if (isSelf && !inst.isPaid)
                    ElevatedButton.icon(
                      onPressed: () => _payInstallmentViaGPay(event, inst),
                      icon: const Icon(Icons.bolt_rounded, size: 14, color: Colors.white),
                      label: const Text('Pay via GPay', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E56A0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    )
                  else
                    IconButton(
                      icon: Icon(
                        inst.isPaid ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                        color: inst.isPaid ? const Color(0xFF2E7D32) : Colors.grey,
                        size: 22,
                      ),
                      tooltip: inst.isPaid ? 'Mark as Unpaid' : 'Mark as Paid',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () async {
                        await eventProvider.toggleInstallmentPaid(inst);
                        _loadData();
                      },
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // --- Expenses Tab ---

  Widget _buildExpensesTab(
    BuildContext context,
    EventModel event,
    List<ExpenseModel> expenses,
  ) {
    if (expenses.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No Expenses Recorded Yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap "Add Expense" below to add flights, hotel, dinner, drinks, or any bills.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () async {
                  final added = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (ctx) => AddExpenseScreen(event: event),
                    ),
                  );
                  if (added == true && mounted) {
                    _loadData(syncWithDrive: false);
                  }
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add First Expense'),
              ),
            ],
          ),
        ),
      );
    }

    final categoryProvider = context.watch<CategoryProvider>();

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: expenses.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final exp = expenses[index];
        final payer = event.members.cast<PersonModel?>().firstWhere(
              (m) => m?.id == exp.payerId,
              orElse: () => null,
            );
        final payerName = payer != null ? (payer.isSelf ? 'You' : payer.name) : 'Unknown';
        final catIcon = categoryProvider.getExpenseIcon(exp.category);
        final catColor = categoryProvider.getExpenseColor(exp.category);

        return Dismissible(
          key: ValueKey('expense_${exp.id}'),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) => _confirmDeleteExpense(exp, event),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade600,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.delete_outline_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Delete',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          child: Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: catColor.withValues(alpha: 0.15),
                child: Icon(catIcon, color: catColor),
              ),
              title: Text(
                exp.title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    'Paid by $payerName • ${DateFormat("dd MMM").format(exp.date)}',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
                  ),
                  if (exp.location != null && exp.location!.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.place_rounded, size: 13, color: Color(0xFFE53935)),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            exp.location!.trim(),
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary(context),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (exp.receiptPath != null && exp.receiptPath!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    GestureDetector(
                      onTap: () => _showReceiptImage(context, exp.receiptPath!),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_camera_rounded, size: 13, color: Color(0xFF1E56A0)),
                          SizedBox(width: 3),
                          Text(
                            'Bill attached • Tap to view',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF1E56A0),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Builder(
                    builder: (context) {
                      final totalHeadcount = exp.splits.fold<int>(0, (sum, s) {
                        final member = event.members.cast<PersonModel?>().firstWhere(
                              (m) => m?.id == s.personId,
                              orElse: () => null,
                            );
                        return sum + (member != null && member.count > 0 ? member.count : 1);
                      });
                      final subtitleText = totalHeadcount > exp.splits.length
                          ? 'Split ${exp.splitType.displayName} among ${exp.splits.length} members ($totalHeadcount people)'
                          : 'Split ${exp.splitType.displayName} among ${exp.splits.length} people';
                      return Text(
                        subtitleText,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF00A896), fontWeight: FontWeight.w500),
                      );
                    },
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (exp.receiptPath != null && exp.receiptPath!.isNotEmpty) ...[
                    IconButton(
                      icon: const Icon(Icons.receipt_long_rounded, color: Color(0xFF1E56A0), size: 20),
                      tooltip: 'View bill photo',
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      onPressed: () => _showReceiptImage(context, exp.receiptPath!),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    CurrencyFormatter.format(exp.amount, symbol: event.currency),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, size: 20, color: AppTheme.textSecondary(context)),
                    tooltip: 'Expense options',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (action) async {
                      if (action == 'edit') {
                        final updated = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (ctx) => AddExpenseScreen(
                              event: event,
                              existingExpense: exp,
                            ),
                          ),
                        );
                        if (updated == true && mounted) {
                          _loadData(syncWithDrive: false);
                        }
                      } else if (action == 'delete') {
                        await _confirmDeleteExpense(exp, event);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              onTap: () async {
                final updated = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (ctx) => AddExpenseScreen(
                      event: event,
                      existingExpense: exp,
                    ),
                  ),
                );
                if (updated == true && mounted) {
                  _loadData(syncWithDrive: false);
                }
              },
            ),
          ),
        );
      },
    );
  }

  // --- Balances Tab ---

  Widget _buildBalancesTab(
    BuildContext context,
    EventModel event,
    dynamic financialSummary,
  ) {
    if (financialSummary == null || financialSummary.memberBalances.isEmpty) {
      return const Center(child: Text('No balances available'));
    }

    final balances = financialSummary.memberBalances;

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: balances.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final b = balances[index];
        final isOwed = b.isOwed;
        final net = b.netBalance;

        Color statusColor;
        String statusText;

        if (b.isSettled) {
          statusColor = Colors.grey;
          statusText = 'Settled up';
        } else if (isOwed) {
          statusColor = const Color(0xFF2E7D32);
          statusText = b.person.isSelf ? 'You get back' : 'Gets back';
        } else {
          statusColor = const Color(0xFFD32F2F);
          statusText = b.person.isSelf ? 'You owe' : 'Owes';
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AvatarHelper.getColorForName(b.person.name),
                  child: Text(
                    AvatarHelper.getInitials(b.person.name),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.person.isSelf ? '${b.person.name} (You)' : b.person.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Paid: ${CurrencyFormatter.format(b.totalPaid, symbol: event.currency)}  •  Share: ${CurrencyFormatter.format(b.totalOwed, symbol: event.currency)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      b.isSettled
                          ? '₹0.00'
                          : CurrencyFormatter.format(net.abs(), symbol: event.currency),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusText,
                      style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Settle Up Tab ---

  Widget _buildSettleUpTab(
    BuildContext context,
    EventModel event,
    List<dynamic> proposals,
    List<dynamic> settlements,
  ) {
    final typedProposals = proposals.cast<SettlementProposal>();
    final myDebts = typedProposals.where((p) => p.from.isSelf).toList();
    final myCredits = typedProposals.where((p) => p.to.isSelf).toList();
    final otherDebts = typedProposals.where((p) => !p.from.isSelf && !p.to.isSelf).toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Suggested Settlements',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: () async {
                  final recorded = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => RecordSettlementDialog(event: event),
                  );
                  if (recorded == true) _loadData();
                },
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: const Text('Custom Payment'),
              ),
            ],
          ),
          Text(
            'FairShare uses debt simplification to minimize total transactions required.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
          ),
          const SizedBox(height: 12),

          if (proposals.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF14532D).withValues(alpha: 0.3) : Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? const Color(0xFF16A34A).withValues(alpha: 0.4) : Colors.green.shade200,
                  width: 0.9,
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 48),
                  const SizedBox(height: 10),
                  Text(
                    event.isArchived ? 'Split Completed! 🎉' : 'All Settled Up! 🎉',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    event.isArchived
                        ? 'All member debts were settled and this event is saved in your History.'
                        : 'No outstanding debts remaining. You can now complete the split to move this event to History.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary(context),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (!event.isArchived)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 1,
                      ),
                      icon: const Icon(Icons.task_alt_rounded, size: 20),
                      label: const Text(
                        'Split Complete',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => _confirmCompleteSplit(context, event),
                    )
                  else
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1E56A0),
                        side: const BorderSide(color: Color(0xFF1E56A0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.unarchive_outlined, size: 18),
                      label: const Text('Reopen Event'),
                      onPressed: () => _confirmReopenEvent(context, event),
                    ),
                ],
              ),
            )
          else ...[
            // 1. My Pending Payments (Current User needs to pay Receiver)
            if (myDebts.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8, top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF7C2D12).withValues(alpha: 0.25) : const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? const Color(0xFFEA580C).withValues(alpha: 0.3) : const Color(0xFFFED7AA),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.priority_high_rounded, size: 16, color: Color(0xFFEA580C)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You have ${myDebts.length} pending ${myDebts.length == 1 ? "payment" : "payments"} to settle with receivers.',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFEA580C),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ...myDebts.map((p) => SettlementCard(
                    event: event,
                    proposal: p,
                  )),
              const SizedBox(height: 12),
            ],

            // 2. Pending Payments Owed To Me
            if (myCredits.isNotEmpty) ...[
              if (myDebts.isNotEmpty) ...[
                const Text(
                  'Payments Owed to You',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
              ],
              ...myCredits.map((p) => SettlementCard(
                    event: event,
                    proposal: p,
                  )),
              const SizedBox(height: 12),
            ],

            // 3. Other Group Settlements
            if (otherDebts.isNotEmpty) ...[
              if (myDebts.isNotEmpty || myCredits.isNotEmpty) ...[
                const Text(
                  'Other Group Settlements',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
              ],
              ...otherDebts.map((p) => SettlementCard(
                    event: event,
                    proposal: p,
                  )),
              const SizedBox(height: 12),
            ],

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF78350F).withValues(alpha: 0.25) : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFFD97706).withValues(alpha: 0.3) : Colors.amber.shade200,
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: isDark ? const Color(0xFFFBBF24) : Colors.amber.shade900, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Settle all ${proposals.length} remaining transactions to enable "Split Complete" and move this event to History.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? const Color(0xFFFBBF24) : Colors.amber.shade900,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (settlements.isNotEmpty) ...[
            const SizedBox(height: 28),
            const Text(
              'Settlement History',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border(context)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: settlements.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
                itemBuilder: (context, index) {
                  final set = settlements[index];
                  final payer = event.members.cast<PersonModel?>().firstWhere(
                        (m) => m?.id == set.payerId,
                        orElse: () => null,
                      );
                  final payee = event.members.cast<PersonModel?>().firstWhere(
                        (m) => m?.id == set.payeeId,
                        orElse: () => null,
                      );

                  final payerName = payer != null ? (payer.isSelf ? 'You' : payer.name) : 'Someone';
                  final payeeName = payee != null ? (payee.isSelf ? 'You' : payee.name) : 'Someone';

                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE8F5E9),
                      child: Icon(Icons.check_rounded, color: Color(0xFF2E7D32)),
                    ),
                    title: Text('$payerName paid $payeeName'),
                    subtitle: Text(
                      '${set.note.isNotEmpty ? "${set.note} • " : ""}${DateFormat("dd MMM yyyy").format(set.settledAt)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Text(
                      CurrencyFormatter.format(set.amount, symbol: event.currency),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmCompleteSplit(BuildContext context, EventModel event) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.task_alt_rounded, color: Color(0xFF2E7D32), size: 24),
            SizedBox(width: 8),
            Text('Complete Split'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mark "${event.title}" as complete and move to History?',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 10),
            const Text(
              'All member debts and balances have been settled. Marking this event as split complete will archive it into your History tab.',
              style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final provider = context.read<EventProvider>();
              final messenger = ScaffoldMessenger.of(context);
              await provider.completeSplitAndArchive(event.id);
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('"${event.title}" moved to History! 🎉'),
                    backgroundColor: const Color(0xFF2E7D32),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                _loadData();
              }
            },
            child: const Text('Move to History'),
          ),
        ],
      ),
    );
  }

  void _confirmReopenEvent(BuildContext context, EventModel event) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reopen Event'),
        content: Text(
          'Move "${event.title}" back from History to Active Events?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E56A0),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final provider = context.read<EventProvider>();
              final messenger = ScaffoldMessenger.of(context);
              await provider.unarchiveEvent(event.id);
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('"${event.title}" restored to Active Events.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                _loadData();
              }
            },
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
  }

  void _showReceiptImage(BuildContext context, String receiptPath) {
    final file = File(receiptPath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt image file not found')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: InteractiveViewer(
                maxScale: 4.0,
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor.withValues(alpha: isDark ? 0.88 : 0.92),
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: shrinkOffset > 0 ? 0.35 : 0.08),
                width: 0.8,
              ),
            ),
          ),
          child: _tabBar,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return true;
  }
}
