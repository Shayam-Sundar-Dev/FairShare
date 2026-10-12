import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/avatar_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/event_model.dart';
import '../../../data/models/person_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/event_provider.dart';
import '../../providers/people_provider.dart';
import '../people/add_person_dialog.dart';
import '../people/contact_picker_sheet.dart';

class AddEventScreen extends StatefulWidget {
  final EventModel? existingEvent;

  const AddEventScreen({super.key, this.existingEvent});

  @override
  State<AddEventScreen> createState() => _AddEventScreenState();
}

class _AddEventScreenState extends State<AddEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _budgetController = TextEditingController();

  late String _selectedCategory;
  String _selectedCurrency = '₹';
  final Set<String> _selectedMemberIds = {};
  final Map<String, int> _memberCounts = {};
  bool _isPlanningTrip = false;
  int _installmentsCount = 3;
  bool _isSaving = false;

  final List<String> _currencies = ['₹', '\$', '€', '£', 'AED', 'SGD', 'CAD', 'AUD'];

  @override
  void initState() {
    super.initState();
    final event = widget.existingEvent;
    if (event != null) {
      _titleController.text = event.title;
      _descriptionController.text = event.description;
      _selectedCategory = event.eventType;
      _selectedCurrency = event.currency;
      _isPlanningTrip = event.isPlanning;
      if (event.estimatedBudget > 0) {
        _budgetController.text = event.estimatedBudget.toStringAsFixed(0);
      }
      _installmentsCount = event.installmentsCount > 0 ? event.installmentsCount : 3;
      _selectedMemberIds.addAll(event.members.map((m) => m.id));
      for (final m in event.members) {
        _memberCounts[m.id] = m.count;
      }
    } else {
      _selectedCategory = EventCategories.trip;
      // Preselect self if available
      final peopleProvider = context.read<PeopleProvider>();
      final self = peopleProvider.selfPerson;
      if (self != null) {
        _selectedMemberIds.add(self.id);
        _memberCounts[self.id] = 1;
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  void _onPersonAdded(PersonModel person) {
    setState(() {
      _selectedMemberIds.add(person.id);
      _memberCounts[person.id] = 1;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMemberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or add at least one member to the event.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final double estimatedBudget = _isPlanningTrip
        ? (double.tryParse(_budgetController.text.trim()) ?? 0.0)
        : 0.0;

    if (_isPlanningTrip && estimatedBudget <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an estimated target budget for the trip plan.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final eventProvider = context.read<EventProvider>();

    try {
      final String status = _isPlanningTrip
          ? 'planning'
          : (widget.existingEvent?.status == 'planning' ? 'active' : (widget.existingEvent?.status ?? 'active'));

      if (widget.existingEvent != null) {
        final updated = widget.existingEvent!.copyWith(
          title: _titleController.text.trim(),
          eventType: _selectedCategory,
          currency: _selectedCurrency,
          description: _descriptionController.text.trim(),
          status: status,
          estimatedBudget: estimatedBudget,
          installmentsCount: _isPlanningTrip ? _installmentsCount : 1,
        );
        await eventProvider.updateEvent(
          event: updated,
          memberPersonIds: _selectedMemberIds.toList(),
          memberCounts: _memberCounts,
        );
      } else {
        final authProvider = context.read<AuthProvider>();
        await eventProvider.createEvent(
          title: _titleController.text.trim(),
          eventType: _selectedCategory,
          currency: _selectedCurrency,
          description: _descriptionController.text.trim(),
          memberPersonIds: _selectedMemberIds.toList(),
          memberCounts: _memberCounts,
          status: status,
          estimatedBudget: estimatedBudget,
          installmentsCount: _isPlanningTrip ? _installmentsCount : 1,
          creatorId: authProvider.currentUser?.id,
          creatorEmail: authProvider.currentUser?.email,
        );
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(widget.existingEvent != null
                ? 'Event updated successfully'
                : (_isPlanningTrip ? 'Trip plan created successfully!' : 'Event created successfully')),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving event: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildTripPlanningSection(Color textPrimary, Color textSecondary, Color cardBg, Color borderColor) {
    final double budget = double.tryParse(_budgetController.text.trim()) ?? 0.0;
    final int totalShares = _selectedMemberIds.fold<int>(
      0,
      (sum, id) => sum + (_memberCounts[id] ?? 1),
    );
    final int safeShares = totalShares > 0 ? totalShares : 1;
    final double perPersonTotal = budget / safeShares;
    final double perInstallment = _installmentsCount > 0 ? perPersonTotal / _installmentsCount : 0.0;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: isDark ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.flight_takeoff_rounded, color: primaryColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trip Budget & Installment Plan',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                    Text(
                      'Collect funds in milestones before starting the trip',
                      style: TextStyle(fontSize: 11.5, color: textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Estimated Total Budget Field
          TextFormField(
            controller: _budgetController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Estimated Total Budget *',
              hintText: 'e.g. 50000',
              prefixText: '$_selectedCurrency ',
              prefixStyle: TextStyle(fontWeight: FontWeight.bold, color: primaryColor, fontSize: 16),
              prefixIcon: const Icon(Icons.account_balance_wallet_rounded),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),

          // Quick Budget Chips
          Wrap(
            spacing: 8,
            children: [10000, 25000, 50000, 100000].map((amt) {
              return ActionChip(
                label: Text('+${CurrencyFormatter.format(amt.toDouble(), symbol: _selectedCurrency)}'),
                labelStyle: TextStyle(fontSize: 11, color: primaryColor),
                backgroundColor: cardBg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                onPressed: () {
                  final current = double.tryParse(_budgetController.text.trim()) ?? 0.0;
                  final next = current + amt;
                  _budgetController.text = next.toStringAsFixed(0);
                  setState(() {});
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Installments Counter
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Number of Installments',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: textPrimary),
                  ),
                  Text(
                    'Milestones to collect before trip',
                    style: TextStyle(fontSize: 11, color: textSecondary),
                  ),
                ],
              ),
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_rounded, size: 18),
                      onPressed: _installmentsCount > 1
                          ? () => setState(() => _installmentsCount--)
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '$_installmentsCount',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryColor),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_rounded, size: 18),
                      onPressed: _installmentsCount < 12
                          ? () => setState(() => _installmentsCount++)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Live Dynamic Calculation Breakdown Card
          if (budget > 0) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Estimated Target:', style: TextStyle(fontSize: 12, color: textSecondary)),
                      Text(
                        CurrencyFormatter.format(budget, symbol: _selectedCurrency),
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Traveling Shares:', style: TextStyle(fontSize: 12, color: textSecondary)),
                      Text(
                        '${_selectedMemberIds.length} members ($totalShares shares)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textPrimary),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Per Person Total:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: textPrimary)),
                      Text(
                        '~ ${CurrencyFormatter.format(perPersonTotal, symbol: _selectedCurrency)}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Per Installment / Share:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: primaryColor)),
                      Text(
                        '${CurrencyFormatter.format(perInstallment, symbol: _selectedCurrency)} / installment',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final peopleProvider = context.watch<PeopleProvider>();
    final categoryProvider = context.watch<CategoryProvider>();
    final allPeople = peopleProvider.people;
    final eventCategories = categoryProvider.eventCategories;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final cardBg = AppTheme.cardBg(context);
    final borderColor = AppTheme.border(context);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingEvent != null
            ? 'Edit Event'
            : (_isPlanningTrip ? 'Plan Upcoming Trip' : 'Create New Event')),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _submit,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Trip Mode Segmented Selection
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _isPlanningTrip = false),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: !_isPlanningTrip ? primaryColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.flash_on_rounded,
                                size: 16,
                                color: !_isPlanningTrip ? Colors.white : textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Standard Split',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: !_isPlanningTrip ? Colors.white : textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() {
                          _isPlanningTrip = true;
                          _selectedCategory = EventCategories.trip;
                        }),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _isPlanningTrip ? primaryColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.flight_takeoff_rounded,
                                size: 16,
                                color: _isPlanningTrip ? Colors.white : textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Plan Upcoming Trip',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: _isPlanningTrip ? Colors.white : textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Event Title
              TextFormField(
                controller: _titleController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: _isPlanningTrip ? 'Trip Name *' : 'Event Title *',
                  hintText: _isPlanningTrip
                      ? 'e.g., Goa Vacation, Ladakh Expedition'
                      : 'e.g., Manali Trip, Rahul’s Birthday, Flat 402',
                  prefixIcon: Icon(_isPlanningTrip ? Icons.flight_rounded : Icons.event_note_rounded),
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Please enter a title' : null,
              ),
              const SizedBox(height: 16),

              // Currency & Note Row
              Row(
                children: [
                  // Currency dropdown
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedCurrency,
                      decoration: const InputDecoration(
                        labelText: 'Currency',
                      ),
                      items: _currencies.map((c) {
                        return DropdownMenuItem(value: c, child: Text(c));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedCurrency = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Description
                  Expanded(
                    child: TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Note / Description (Optional)',
                        hintText: 'e.g., Weekend getaway',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Planning Section (when _isPlanningTrip is true)
              if (_isPlanningTrip)
                _buildTripPlanningSection(textPrimary, textSecondary, cardBg, borderColor),

              // Category Choice Chips (if not planning or allow changing)
              if (!_isPlanningTrip) ...[
                const Text(
                  'Event Category',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...(eventCategories.isNotEmpty
                        ? eventCategories.map((cat) {
                            final isSelected = cat.name == _selectedCategory;
                            final catColor = cat.color;
                            return ChoiceChip(
                              avatar: Icon(
                                cat.icon,
                                size: 16,
                                color: isSelected ? Colors.white : catColor,
                              ),
                              label: Text(cat.name),
                              selected: isSelected,
                              selectedColor: catColor,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              onSelected: (_) => setState(() => _selectedCategory = cat.name),
                            );
                          })
                        : EventCategories.all.map((cat) {
                            final isSelected = cat == _selectedCategory;
                            final catColor = EventCategories.getColor(cat);
                            return ChoiceChip(
                              avatar: Icon(
                                EventCategories.getIcon(cat),
                                size: 16,
                                color: isSelected ? Colors.white : catColor,
                              ),
                              label: Text(cat),
                              selected: isSelected,
                              selectedColor: catColor,
                              labelStyle: TextStyle(
                                color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              onSelected: (_) => setState(() => _selectedCategory = cat),
                            );
                          })),
                  ],
                ),
                const SizedBox(height: 28),
              ],

              // Members Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        () {
                          final totalPeopleCount = _selectedMemberIds.fold<int>(
                            0,
                            (sum, id) => sum + (_memberCounts[id] ?? 1),
                          );
                          return 'Members (${_selectedMemberIds.length} · $totalPeopleCount ${totalPeopleCount == 1 ? "person" : "people"})';
                        }(),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Set number of people per member for accurate split',
                        style: TextStyle(fontSize: 11.5, color: textSecondary),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Add from contacts button
                      IconButton.filledTonal(
                        tooltip: 'Add from Contacts',
                        icon: const Icon(Icons.contacts_rounded, size: 20),
                        onPressed: () {
                          ContactPickerSheet.show(
                            context,
                            onPersonSelected: _onPersonAdded,
                            onPeopleSelected: (peopleList) {
                              setState(() {
                                for (final p in peopleList) {
                                  _selectedMemberIds.add(p.id);
                                  _memberCounts[p.id] = _memberCounts[p.id] ?? 1;
                                }
                              });
                            },
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      // Add manually with mobile number
                      IconButton.filledTonal(
                        tooltip: 'Type Mobile Number',
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AddPersonDialog(
                              onPersonAdded: _onPersonAdded,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Members List
              allPeople.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.group_add_rounded, size: 40, color: textSecondary),
                          const SizedBox(height: 8),
                          Text(
                            'No members available yet.',
                            style: TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () {
                                  ContactPickerSheet.show(
                                    context,
                                    onPersonSelected: _onPersonAdded,
                                    onPeopleSelected: (peopleList) {
                                      setState(() {
                                        for (final p in peopleList) {
                                          _selectedMemberIds.add(p.id);
                                          _memberCounts[p.id] = _memberCounts[p.id] ?? 1;
                                        }
                                      });
                                    },
                                  );
                                },
                                icon: const Icon(Icons.contacts_rounded, size: 16),
                                label: const Text('From Contacts'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AddPersonDialog(
                                      onPersonAdded: _onPersonAdded,
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.dialpad_rounded, size: 16),
                                label: const Text('Type Number'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: allPeople.length,
                        separatorBuilder: (_, _) => Divider(height: 1, indent: 68, color: borderColor),
                        itemBuilder: (context, index) {
                          final person = allPeople[index];
                          final isSelected = _selectedMemberIds.contains(person.id);
                          final count = _memberCounts[person.id] ?? 1;

                          return InkWell(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedMemberIds.remove(person.id);
                                } else {
                                  _selectedMemberIds.add(person.id);
                                  _memberCounts[person.id] = _memberCounts[person.id] ?? 1;
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  // Selection Checkbox
                                  Checkbox(
                                    value: isSelected,
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          _selectedMemberIds.add(person.id);
                                          _memberCounts[person.id] = _memberCounts[person.id] ?? 1;
                                        } else {
                                          _selectedMemberIds.remove(person.id);
                                        }
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 4),

                                  // Avatar
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: AvatarHelper.getColorForName(person.name),
                                    child: Text(
                                      AvatarHelper.getInitials(person.name),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Name & Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                person.isSelf ? '${person.name} (You)' : person.name,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: isSelected ? textPrimary : textSecondary,
                                                  fontSize: 14,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (person.isSelf) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: primaryColor.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'YOU',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    color: primaryColor,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          person.phoneNumber.isNotEmpty
                                              ? person.phoneNumber
                                              : (person.isSelf ? 'Personal profile' : 'No phone number'),
                                          style: TextStyle(fontSize: 11.5, color: textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Quantity / Headcount Stepper when selected
                                  if (isSelected)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          InkWell(
                                            onTap: count > 1
                                                ? () {
                                                    setState(() {
                                                      _memberCounts[person.id] = count - 1;
                                                    });
                                                  }
                                                : null,
                                            borderRadius: BorderRadius.circular(6),
                                            child: Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: Icon(
                                                Icons.remove_rounded,
                                                size: 16,
                                                color: count > 1
                                                    ? primaryColor
                                                    : (isDark ? Colors.white24 : Colors.grey.shade400),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 6),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  '$count',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: primaryColor,
                                                  ),
                                                ),
                                                Text(
                                                  count == 1 ? 'person' : 'people',
                                                  style: TextStyle(
                                                    fontSize: 8.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          InkWell(
                                            onTap: count < 99
                                                ? () {
                                                    setState(() {
                                                      _memberCounts[person.id] = count + 1;
                                                    });
                                                  }
                                                : null,
                                            borderRadius: BorderRadius.circular(6),
                                            child: Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: Icon(
                                                Icons.add_rounded,
                                                size: 16,
                                                color: count < 99
                                                    ? primaryColor
                                                    : (isDark ? Colors.white24 : Colors.grey.shade400),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
