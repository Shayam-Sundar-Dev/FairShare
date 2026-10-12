import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/phone_helper.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../data/models/event_model.dart';
import '../../../data/models/expense_model.dart';
import '../../../data/models/person_model.dart';
import '../../../data/repositories/people_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/location_service.dart';
import '../../../domain/algorithms/split_calculator.dart';
import '../../providers/category_provider.dart';
import '../../providers/event_provider.dart';
import '../../providers/expense_provider.dart';
import '../../providers/people_provider.dart';
import '../../providers/trip_sync_provider.dart';
import '../categories/manage_categories_screen.dart';
import 'widgets/split_selector_widget.dart';

class AddExpenseScreen extends StatefulWidget {
  final EventModel event;
  final ExpenseModel? existingExpense;

  const AddExpenseScreen({
    super.key,
    required this.event,
    this.existingExpense,
  });

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  String? _detectedLocation;
  double? _latitude;
  double? _longitude;
  bool _isFetchingLocation = false;
  final _locationService = LocationService();

  String? _receiptPath;
  final ImagePicker _imagePicker = ImagePicker();

  late String _selectedPayerId;
  late String _selectedCategory;
  late DateTime _selectedDate;
  late SplitType _splitType;
  List<String> _selectedMemberIds = [];
  Map<String, double> _rawInputs = {};
  bool _isSplitValid = true;
  bool _isSaving = false;
  bool _hasUserManuallySelectedCategory = false;

  @override
  void initState() {
    super.initState();
    final expense = widget.existingExpense;
    if (expense != null) {
      _hasUserManuallySelectedCategory = true;
      _titleController.text = expense.title;
      _amountController.text = expense.amount.toString();
      _selectedPayerId = expense.payerId;
      _selectedCategory = expense.category;
      _selectedDate = expense.date;
      _splitType = expense.splitType;
      _selectedMemberIds = expense.splits.map((s) => s.personId).toList();
      _rawInputs = {for (var s in expense.splits) s.personId: s.rawValue};
      _detectedLocation = expense.location;
      _latitude = expense.latitude;
      _longitude = expense.longitude;
      _receiptPath = expense.receiptPath;
    } else {
      _hasUserManuallySelectedCategory = false;
      _titleController.text = '';
      _amountController.text = '';
      // Default payer is 'You' or member matching self phone or first member
      final selfP = context.read<PeopleProvider>().selfPerson;
      final selfPhone = selfP?.phoneNumber ?? '';
      final selfMember = widget.event.members.cast<PersonModel?>().firstWhere(
            (m) => m?.isSelf == true || (selfPhone.isNotEmpty && m != null && PhoneHelper.isSamePhone(m.phoneNumber, selfPhone)),
            orElse: () => widget.event.members.isNotEmpty ? widget.event.members.first : null,
          );
      _selectedPayerId = selfMember?.id ?? '';
      _selectedCategory = ExpenseCategories.food;
      _selectedDate = DateTime.now();
      _splitType = SplitType.equal;
      _selectedMemberIds = widget.event.members.map((m) => m.id).toList();
      _rawInputs = {};
      // Automatically detect current GPS location in background whenever adding an expense
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchCurrentLocation();
      });
    }

    _titleController.addListener(_onTitleChanged);
  }

  void _onTitleChanged() {
    if (_hasUserManuallySelectedCategory) return;
    final title = _titleController.text.trim().toLowerCase();
    if (title.isEmpty) return;

    final detected = _detectCategoryFromTitle(title);
    if (detected != null && detected != _selectedCategory) {
      setState(() {
        _selectedCategory = detected;
      });
    }
  }

  String? _detectCategoryFromTitle(String text) {
    if (RegExp(r'\b(flight|air|plane|train|metro|bus|cab|taxi|uber|ola|auto|petrol|diesel|fuel|toll|transport|travel|drive|ticket|fare|commute)\b').hasMatch(text)) {
      return ExpenseCategories.travel;
    }
    if (RegExp(r'\b(hotel|stay|resort|airbnb|room|hostel|lodge|oyo|homestay|cottage|villa|camp|tent|booking)\b').hasMatch(text)) {
      return ExpenseCategories.stay;
    }
    if (RegExp(r'\b(movie|cinema|film|theatre|theater|game|bowling|concert|show|party|club|pub|netflix|spotify|event|amusement|museum|zoo)\b').hasMatch(text)) {
      return ExpenseCategories.entertainment;
    }
    if (RegExp(r'\b(shop|shopping|market|store|mall|clothes|cloth|shirt|pant|shoes|dress|amazon|flipkart|myntra|zara|grocery|groceries|supermarket|mart)\b').hasMatch(text)) {
      return ExpenseCategories.shopping;
    }
    if (RegExp(r'\b(bill|bills|electricity|power|water|wifi|internet|broadband|recharge|mobile|phone|gas|cylinder|rent|maintenance|utility|utilities)\b').hasMatch(text)) {
      return ExpenseCategories.bills;
    }
    if (RegExp(r'\b(food|eat|dinner|lunch|breakfast|snack|snacks|tea|coffee|cafe|restaurant|burger|pizza|biryani|roti|meal|drink|drinks|beer|wine|liquor|bar|swiggy|zomato|kfc|mcdonald|domino|starbucks)\b').hasMatch(text)) {
      return ExpenseCategories.food;
    }
    return null;
  }

  @override
  void dispose() {
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    if (!mounted) return;
    setState(() => _isFetchingLocation = true);
    final result = await _locationService.getCurrentLocation();
    if (mounted) {
      if (result != null) {
        _latitude = result.latitude;
        _longitude = result.longitude;
        _detectedLocation = result.locationName;
      }
      setState(() => _isFetchingLocation = false);
    }
  }

  Future<void> _captureBill(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1800,
        maxHeight: 1800,
      );
      if (picked != null && mounted) {
        setState(() {
          _receiptPath = picked.path;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not access camera/gallery: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text(
                  'Attach Physical Bill Receipt',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Capture paper bill with camera or pick from photo library',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E56A0).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF1E56A0)),
                  ),
                  title: const Text('Capture with Camera', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Take a photo of physical bill / receipt'),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _captureBill(ImageSource.camera);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A896).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.photo_library_rounded, color: Color(0xFF00A896)),
                  ),
                  title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Select receipt photo or digital invoice'),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _captureBill(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showReceiptPreviewDialog(String path) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
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
                    File(path),
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
        );
      },
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _saveExpense() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount greater than 0')),
      );
      return;
    }

    // Recalculate and validate splits
    final memberCounts = {
      for (final m in widget.event.members) m.id: (m.count > 0 ? m.count : 1),
    };
    final splitResult = SplitCalculator.calculateSplits(
      expenseId: widget.existingExpense?.id ?? '',
      totalAmount: amount,
      splitType: _splitType,
      selectedPersonIds: _selectedMemberIds,
      rawInputs: _rawInputs,
      personCounts: memberCounts,
    );

    if (!splitResult.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(splitResult.errorMessage ?? 'Invalid split distribution'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final expenseProvider = context.read<ExpenseProvider>();
    final eventProvider = context.read<EventProvider>();
    final syncProvider = context.read<TripSyncProvider>();

    try {
      if (widget.existingExpense != null) {
        final updatedExpense = widget.existingExpense!.copyWith(
          payerId: _selectedPayerId,
          title: _titleController.text.trim(),
          amount: amount,
          category: _selectedCategory,
          splitType: _splitType,
          date: _selectedDate,
          location: _detectedLocation,
          latitude: _latitude,
          longitude: _longitude,
          receiptPath: _receiptPath,
          clearReceiptPath: _receiptPath == null,
        );
        await expenseProvider.updateExpense(
          expense: updatedExpense,
          splits: splitResult.splits,
        );
      } else {
        final selfPerson = context.read<PeopleProvider>().selfPerson ?? await PeopleRepository().getSelfPerson();
        final authUser = await AuthService().getCurrentUser();
        final effectivePhone = (selfPerson?.phoneNumber.isNotEmpty == true)
            ? selfPerson!.phoneNumber
            : (authUser?.phoneNumber ?? '');

        PersonModel? myMember;
        if (effectivePhone.isNotEmpty) {
          myMember = widget.event.members.cast<PersonModel?>().firstWhere(
            (m) => m != null && PhoneHelper.isSamePhone(m.phoneNumber, effectivePhone),
            orElse: () => null,
          );
        }
        if (myMember == null && selfPerson != null) {
          myMember = widget.event.members.cast<PersonModel?>().firstWhere(
            (m) => m != null && (m.isSelf || m.id == selfPerson.id),
            orElse: () => null,
          );
        }
        final effectiveSubmittedById = myMember?.id ?? selfPerson?.id;
        final effectiveSubmittedByName = myMember?.name ?? selfPerson?.name ?? authUser?.displayName ?? 'Me';

        await expenseProvider.addExpense(
          eventId: widget.event.id,
          payerId: _selectedPayerId,
          title: _titleController.text.trim(),
          amount: amount,
          category: _selectedCategory,
          splitType: _splitType,
          date: _selectedDate,
          location: _detectedLocation,
          latitude: _latitude,
          longitude: _longitude,
          receiptPath: _receiptPath,
          splits: splitResult.splits,
          submittedByPersonId: effectiveSubmittedById,
          submittedByName: effectiveSubmittedByName,
        );
      }

      await Future.wait([
        eventProvider.computeFinancials(widget.event.id),
        eventProvider.refreshEventInList(widget.event.id),
      ]);

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop(true);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              widget.existingExpense != null ? 'Expense updated' : 'Expense added',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      if (widget.event.isShared || (widget.event.driveFileId != null && widget.event.driveFileId!.isNotEmpty)) {
        // Automatically sync and push new/updated expense to Google Drive in the background
        syncProvider.syncTrip(
          widget.event,
          eventProvider: eventProvider,
          expenseProvider: expenseProvider,
        ).catchError((e) {
          debugPrint('Background sync error after saving expense: $e');
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving expense: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _confirmDeleteExpense() async {
    final expense = widget.existingExpense;
    if (expense == null) return;

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
          'Are you sure you want to delete "${expense.title}" (${CurrencyFormatter.format(expense.amount, symbol: widget.event.currency)})?\n\nThis will recalculate all group balances.',
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
      setState(() => _isSaving = true);
      try {
        final expenseProvider = context.read<ExpenseProvider>();
        final eventProvider = context.read<EventProvider>();
        final syncProvider = context.read<TripSyncProvider>();

        await expenseProvider.deleteExpense(expense.id, widget.event.id);
        await Future.wait([
          eventProvider.computeFinancials(widget.event.id),
          eventProvider.refreshEventInList(widget.event.id),
        ]);

        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          Navigator.of(context).pop(true);
          messenger.showSnackBar(
            SnackBar(
              content: Text('Expense "${expense.title}" deleted'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 2),
            ),
          );
        }

        if (widget.event.isShared || (widget.event.driveFileId != null && widget.event.driveFileId!.isNotEmpty)) {
          syncProvider.syncTrip(
            widget.event,
            eventProvider: eventProvider,
            expenseProvider: expenseProvider,
          ).catchError((e) {
            debugPrint('Background sync error after deleting expense: $e');
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting expense: $e'), backgroundColor: Colors.red),
          );
          setState(() => _isSaving = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.event.members;
    final currentAmount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final categoryProvider = context.watch<CategoryProvider>();
    final expenseCategories = categoryProvider.expenseCategories;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingExpense != null ? 'Edit Expense' : 'Add Expense'),
        actions: [
          if (widget.existingExpense != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              tooltip: 'Delete Expense',
              onPressed: _isSaving ? null : _confirmDeleteExpense,
            ),
          TextButton(
            onPressed: (_isSaving || !_isSplitValid) ? null : _saveExpense,
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
              // Amount Input Card
              LiquidGlassContainer(
                borderRadius: BorderRadius.circular(16),
                blur: 12,
                borderWidth: 0.9,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  children: [
                    Text(
                      widget.event.currency,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                        decoration: const InputDecoration(
                          hintText: '0.00',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Enter amount';
                          final parsed = double.tryParse(val.trim());
                          if (parsed == null || parsed <= 0) return 'Invalid amount';
                          return null;
                        },
                        onChanged: (val) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Title input
              TextFormField(
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Expense Description *',
                  hintText: 'e.g., Dinner at Bistro, Taxi, Groceries',
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Please enter a description' : null,
              ),
              const SizedBox(height: 16),

              // Physical Bill Receipt Capture Card
              _buildReceiptCard(),
              const SizedBox(height: 16),

              // Auto-detected Location Card (Read-only, user cannot enter manually)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceSubtle(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border(context)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.location_on_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Location (Auto-detected)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (_isFetchingLocation)
                            Row(
                              children: [
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Detecting GPS location...',
                                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(context)),
                                ),
                              ],
                            )
                          else if (_detectedLocation != null && _detectedLocation!.isNotEmpty)
                            Text(
                              _detectedLocation!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary(context),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            )
                          else
                            Text(
                              'Location unavailable',
                              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary(context)),
                            ),
                        ],
                      ),
                    ),
                    if (!_isFetchingLocation)
                      IconButton(
                        icon: Icon(Icons.refresh_rounded, size: 20, color: Theme.of(context).colorScheme.primary),
                        tooltip: 'Re-detect location',
                        onPressed: _fetchCurrentLocation,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Payer & Date Row
              Row(
                children: [
                  // Payer selector
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedPayerId.isNotEmpty ? _selectedPayerId : null,
                      decoration: const InputDecoration(
                        labelText: 'Paid By',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      items: members.map((m) {
                        return DropdownMenuItem(
                          value: m.id,
                          child: Text(
                            m.isSelf ? '${m.name} (You)' : m.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedPayerId = val);
                      },
                      validator: (val) => val == null ? 'Select payer' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Date Picker
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date',
                          prefixIcon: Icon(Icons.calendar_today_rounded),
                        ),
                        child: Text(
                          DateFormat('dd MMM yyyy').format(_selectedDate),
                          style: const TextStyle(fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Category Dropdown
              Builder(
                builder: (context) {
                  // Build all available categories
                  final List<({String name, IconData icon, Color color})> categoryItems = [];
                  if (expenseCategories.isNotEmpty) {
                    for (final c in expenseCategories) {
                      categoryItems.add((name: c.name, icon: c.icon, color: c.color));
                    }
                  } else {
                    for (final name in ExpenseCategories.all) {
                      categoryItems.add((
                        name: name,
                        icon: ExpenseCategories.getIcon(name),
                        color: ExpenseCategories.getColor(name),
                      ));
                    }
                  }

                  // Ensure selected category is present in items even if custom/legacy
                  if (!categoryItems.any((c) => c.name == _selectedCategory)) {
                    categoryItems.insert(0, (
                      name: _selectedCategory,
                      icon: ExpenseCategories.getIcon(_selectedCategory),
                      color: ExpenseCategories.getColor(_selectedCategory),
                    ));
                  }

                  final currentCatItem = categoryItems.firstWhere(
                    (c) => c.name == _selectedCategory,
                    orElse: () => categoryItems.first,
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Category',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (ctx) => const ManageCategoriesScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.tune_rounded, size: 16),
                            label: const Text('Manage', style: TextStyle(fontSize: 13)),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(50, 30),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCategory,
                        isExpanded: true,
                        decoration: InputDecoration(
                          prefixIcon: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: currentCatItem.color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                currentCatItem.icon,
                                color: currentCatItem.color,
                                size: 18,
                              ),
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 46,
                            minHeight: 46,
                          ),
                        ),
                        selectedItemBuilder: (context) {
                          return categoryItems.map((cat) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                cat.name,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList();
                        },
                        items: categoryItems.map((cat) {
                          final isSelected = cat.name == _selectedCategory;
                          return DropdownMenuItem<String>(
                            value: cat.name,
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: cat.color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(cat.icon, size: 16, color: cat.color),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    cat.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected ? cat.color : null,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isSelected)
                                  Icon(Icons.check_rounded, size: 18, color: cat.color),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _selectedCategory = val;
                              _hasUserManuallySelectedCategory = true;
                            });
                          }
                        },
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // Split Selector Widget
              SplitSelectorWidget(
                totalAmount: currentAmount,
                currency: widget.event.currency,
                members: members,
                initialSplitType: _splitType,
                initialSelectedIds: _selectedMemberIds,
                initialRawInputs: _rawInputs,
                onChanged: (type, selectedIds, rawInputs, isValid) {
                  setState(() {
                    _splitType = type;
                    _selectedMemberIds = selectedIds;
                    _rawInputs = rawInputs;
                    _isSplitValid = isValid;
                  });
                },
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptCard() {
    if (_receiptPath != null && _receiptPath!.isNotEmpty) {
      final file = File(_receiptPath!);
      final fileExists = file.existsSync();
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final primaryColor = Theme.of(context).colorScheme.primary;

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF064E3B).withValues(alpha: 0.25) : const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? const Color(0xFF047857).withValues(alpha: 0.4) : const Color(0xFFBBF7D0),
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () {
                if (fileExists) {
                  _showReceiptPreviewDialog(_receiptPath!);
                }
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: fileExists
                        ? Image.file(
                            file,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 64,
                            height: 64,
                            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                            child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
                          ),
                  ),
                  if (fileExists)
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 24),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Physical Bill Attached',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Tap photo to zoom & inspect bill',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppTheme.darkTextSecondary : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      InkWell(
                        onTap: () => _captureBill(ImageSource.camera),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.camera_alt_rounded, size: 14, color: primaryColor),
                              const SizedBox(width: 4),
                              Text(
                                'Retake',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      InkWell(
                        onTap: () => setState(() => _receiptPath = null),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded, size: 14, color: Colors.red),
                              SizedBox(width: 4),
                              Text(
                                'Remove',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
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
    }

    return Builder(
      builder: (context) {
        final primaryColor = Theme.of(context).colorScheme.primary;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceSubtle(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border(context)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Physical Bill / Receipt',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Capture paper bill with camera',
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary(context)),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _captureBill(ImageSource.camera),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.camera_alt_rounded, size: 16),
                label: const Text('Camera', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.more_vert_rounded, size: 20, color: AppTheme.textSecondary(context)),
                tooltip: 'More options',
                onPressed: _showImageSourceSheet,
              ),
            ],
          ),
        );
      },
    );
  }
}
