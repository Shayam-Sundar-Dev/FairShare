import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/event_model.dart';
import '../../../domain/models/settlement_proposal.dart';
import '../../providers/event_provider.dart';
import '../../providers/expense_provider.dart';

class RecordSettlementDialog extends StatefulWidget {
  final EventModel event;
  final SettlementProposal? proposal;

  const RecordSettlementDialog({
    super.key,
    required this.event,
    this.proposal,
  });

  @override
  State<RecordSettlementDialog> createState() => _RecordSettlementDialogState();
}

class _RecordSettlementDialogState extends State<RecordSettlementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  late String _payerId;
  late String _payeeId;
  final DateTime _settledAt = DateTime.now();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.proposal != null) {
      _payerId = widget.proposal!.from.id;
      _payeeId = widget.proposal!.to.id;
      _amountController.text = widget.proposal!.amount.toStringAsFixed(2);
      _noteController.text = 'Settled via UPI / Cash';
    } else {
      final members = widget.event.members;
      _payerId = members.isNotEmpty ? members.first.id : '';
      _payeeId = members.length > 1 ? members[1].id : (members.isNotEmpty ? members.first.id : '');
      _amountController.text = '';
      _noteController.text = '';
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_payerId == _payeeId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payer and Payee cannot be the same person.')),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an amount greater than 0.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final expenseProvider = context.read<ExpenseProvider>();
    final eventProvider = context.read<EventProvider>();

    try {
      await expenseProvider.recordSettlement(
        eventId: widget.event.id,
        payerId: _payerId,
        payeeId: _payeeId,
        amount: amount,
        settledAt: _settledAt,
        note: _noteController.text.trim(),
      );

      await eventProvider.computeFinancials(widget.event.id);
      await eventProvider.loadEvents();

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop(true);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              widget.proposal?.to.isSelf == true
                  ? 'Payment marked as received!'
                  : 'Settlement recorded successfully!',
            ),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to record settlement: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.event.members;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.handshake_rounded, color: Color(0xFF2E7D32)),
          const SizedBox(width: 10),
          Text(
            widget.proposal?.to.isSelf == true ? 'Payment Received' : 'Record Payment',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Payer
              DropdownButtonFormField<String>(
                initialValue: _payerId.isNotEmpty ? _payerId : null,
                decoration: const InputDecoration(
                  labelText: 'Who Paid? (Debtor)',
                  prefixIcon: Icon(Icons.arrow_upward_rounded, color: Colors.red),
                ),
                items: members.map((m) {
                  return DropdownMenuItem(
                    value: m.id,
                    child: Text(m.isSelf ? '${m.name} (You)' : m.name),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _payerId = val);
                },
              ),
              const SizedBox(height: 14),

              // Payee
              DropdownButtonFormField<String>(
                initialValue: _payeeId.isNotEmpty ? _payeeId : null,
                decoration: const InputDecoration(
                  labelText: 'Paid To? (Creditor)',
                  prefixIcon: Icon(Icons.arrow_downward_rounded, color: Colors.green),
                ),
                items: members.map((m) {
                  return DropdownMenuItem(
                    value: m.id,
                    child: Text(m.isSelf ? '${m.name} (You)' : m.name),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _payeeId = val);
                },
              ),
              const SizedBox(height: 14),

              // Amount
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount *',
                  prefixText: widget.event.currency,
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Enter amount';
                  final p = double.tryParse(val.trim());
                  if (p == null || p <= 0) return 'Invalid amount';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Note
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Payment Note',
                  hintText: 'e.g., GPay, Cash, Bank Transfer',
                  prefixIcon: Icon(Icons.note_alt_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(widget.proposal?.to.isSelf == true ? 'Mark Received' : 'Record Settle Up'),
        ),
      ],
    );
  }
}
