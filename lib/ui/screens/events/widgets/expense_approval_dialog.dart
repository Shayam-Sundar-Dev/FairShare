import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/avatar_helper.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../data/models/event_model.dart';
import '../../../../data/models/expense_model.dart';
import '../../../../data/models/person_model.dart';
import '../../../providers/category_provider.dart';
import '../../../providers/event_provider.dart';
import '../../../providers/expense_provider.dart';
import '../../../providers/trip_sync_provider.dart';

class ExpenseApprovalDialog extends StatefulWidget {
  final EventModel event;
  final ExpenseModel expense;

  const ExpenseApprovalDialog({
    super.key,
    required this.event,
    required this.expense,
  });

  @override
  State<ExpenseApprovalDialog> createState() => _ExpenseApprovalDialogState();
}

class _ExpenseApprovalDialogState extends State<ExpenseApprovalDialog> {
  bool _isProcessing = false;

  Future<void> _handleApprove() async {
    setState(() => _isProcessing = true);
    final syncProvider = context.read<TripSyncProvider>();
    final expenseProvider = context.read<ExpenseProvider>();
    final eventProvider = context.read<EventProvider>();

    // 1. Approve via sync provider & repository
    await syncProvider.approveExpense(
      event: widget.event,
      expense: widget.expense,
    );

    // 2. Reload event financials & expenses
    await expenseProvider.loadForEvent(widget.event.id);
    await eventProvider.computeFinancials(widget.event.id);
    await eventProvider.loadEvents();

    if (mounted) {
      setState(() => _isProcessing = false);
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Expense "${widget.expense.title}" approved and added to trip!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    }
  }

  Future<void> _handleReject() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: Colors.red),
            SizedBox(width: 8),
            Text('Reject Expense'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to reject "${widget.expense.title}"?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g. Duplicate bill, incorrect amount',
                border: OutlineInputBorder(),
              ),
            ),
          ],
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
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isProcessing = true);
      final syncProvider = context.read<TripSyncProvider>();
      final expenseProvider = context.read<ExpenseProvider>();
      final eventProvider = context.read<EventProvider>();

      await syncProvider.rejectExpense(
        event: widget.event,
        expense: widget.expense,
        reason: reasonController.text.trim().isNotEmpty ? reasonController.text.trim() : null,
      );

      await expenseProvider.loadForEvent(widget.event.id);
      await eventProvider.computeFinancials(widget.event.id);

      if (mounted) {
        setState(() => _isProcessing = false);
        Navigator.of(context).pop(false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Expense "${widget.expense.title}" was rejected.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryProvider = context.watch<CategoryProvider>();
    final catIcon = categoryProvider.getExpenseIcon(widget.expense.category);
    final catColor = categoryProvider.getExpenseColor(widget.expense.category);
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final payer = widget.event.members.cast<PersonModel?>().firstWhere(
          (m) => m?.id == widget.expense.payerId,
          orElse: () => null,
        );
    final payerName = payer != null ? (payer.isSelf ? 'You' : payer.name) : 'Unknown';
    final submitterName = widget.expense.submittedByName ?? payerName;

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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
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

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade400),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pending_actions_rounded, size: 14, color: Colors.amber.shade900),
                      const SizedBox(width: 4),
                      Text(
                        'Pending Approval',
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('dd MMM yyyy').format(widget.expense.date),
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Expense Card
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: catColor.withValues(alpha: 0.15),
                  child: Icon(catIcon, color: catColor, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.expense.title,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Submitted by $submitterName',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF1E56A0)),
                      ),
                      Text(
                        'Paid by: $payerName',
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                      if (widget.expense.location != null && widget.expense.location!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.place_rounded, size: 13, color: Colors.red),
                            const SizedBox(width: 4),
                            Text(widget.expense.location!, style: TextStyle(fontSize: 12, color: textSecondary)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  CurrencyFormatter.format(widget.expense.amount, symbol: widget.event.currency),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Receipt Photo if attached
            if (widget.expense.receiptPath != null && widget.expense.receiptPath!.isNotEmpty) ...[
              Container(
                height: 140,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border(context)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.file(
                  File(widget.expense.receiptPath!),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Text('Receipt image attached', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Splits breakdown
            Text(
              'Split Breakdown (${widget.expense.splitType.displayName}):',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border(context)),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.expense.splits.length,
                separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.border(context)),
                itemBuilder: (ctx, i) {
                  final split = widget.expense.splits[i];
                  final person = widget.event.members.cast<PersonModel?>().firstWhere(
                        (m) => m?.id == split.personId,
                        orElse: () => null,
                      );
                  final name = person != null ? (person.isSelf ? 'You' : person.name) : 'Member';

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: AvatarHelper.getColorForName(name),
                          child: Text(
                            AvatarHelper.getInitials(name),
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                              if (person != null && person.count > 1)
                                Text(
                                  '${person.count} people',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          CurrencyFormatter.format(split.allocatedAmount, symbol: widget.event.currency),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _handleReject,
                    icon: const Icon(Icons.close_rounded, color: Colors.red),
                    label: const Text('Reject', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _handleApprove,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_rounded),
                    label: Text(_isProcessing ? 'Approving...' : 'Approve & Add'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
