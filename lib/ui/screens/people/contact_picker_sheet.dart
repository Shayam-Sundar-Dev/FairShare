import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/avatar_helper.dart';
import '../../../data/models/person_model.dart';
import '../../../data/services/contacts_service.dart';
import '../../providers/people_provider.dart';
import 'add_person_dialog.dart';

class ContactPickerSheet extends StatefulWidget {
  final Function(PersonModel person)? onPersonSelected;
  final Function(List<PersonModel> people)? onPeopleSelected;

  const ContactPickerSheet({
    super.key,
    this.onPersonSelected,
    this.onPeopleSelected,
  });

  static Future<void> show(
    BuildContext context, {
    Function(PersonModel person)? onPersonSelected,
    Function(List<PersonModel> people)? onPeopleSelected,
  }) async {
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ContactPickerSheet(
        onPersonSelected: onPersonSelected,
        onPeopleSelected: onPeopleSelected,
      ),
    );

    if (result == 'manual' && context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AddPersonDialog(
          onPersonAdded: (p) {
            onPersonSelected?.call(p);
            onPeopleSelected?.call([p]);
          },
        ),
      );
    }
  }

  @override
  State<ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<ContactPickerSheet> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedKeys = {};
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PeopleProvider>().loadDeviceContacts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getContactKey(DeviceContactItem c) {
    if (c.id.isNotEmpty) return c.id;
    return '${c.displayName}_${c.phoneNumbers.join(",")}';
  }

  bool _isAlreadyAdded(DeviceContactItem contact, List<PersonModel> existingPeople) {
    final cName = contact.displayName.trim().toLowerCase();
    final cPhones = contact.phoneNumbers
        .map((p) => p.replaceAll(RegExp(r'\D'), ''))
        .where((p) => p.isNotEmpty)
        .toSet();

    return existingPeople.any((p) {
      final pPhone = p.phoneNumber.replaceAll(RegExp(r'\D'), '');
      if (pPhone.isNotEmpty && cPhones.contains(pPhone)) return true;
      if (p.name.trim().toLowerCase() == cName && cName.isNotEmpty) return true;
      return false;
    });
  }

  void _toggleContact(DeviceContactItem contact) {
    final key = _getContactKey(contact);
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
      } else {
        _selectedKeys.add(key);
      }
    });
  }

  void _toggleSelectAll(List<DeviceContactItem> list) {
    setState(() {
      final allKeys = list.map(_getContactKey).toSet();
      if (_selectedKeys.containsAll(allKeys)) {
        _selectedKeys.removeAll(allKeys);
      } else {
        _selectedKeys.addAll(allKeys);
      }
    });
  }

  Future<void> _handleImportSelected(List<DeviceContactItem> allContacts) async {
    final selectedContacts = allContacts
        .where((c) => _selectedKeys.contains(_getContactKey(c)))
        .toList();

    if (selectedContacts.isEmpty) return;

    setState(() => _isImporting = true);
    final peopleProvider = context.read<PeopleProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final importedPeople =
          await peopleProvider.importMultipleContacts(selectedContacts);

      if (mounted) {
        widget.onPeopleSelected?.call(importedPeople);
        for (final p in importedPeople) {
          widget.onPersonSelected?.call(p);
        }
        navigator.pop(importedPeople);

        messenger.showSnackBar(
          SnackBar(
            content: Text(
              importedPeople.length == 1
                  ? 'Added ${importedPeople.first.name} to friends!'
                  : 'Added ${importedPeople.length} friends from contacts!',
            ),
            backgroundColor: AppTheme.positiveGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isImporting = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to import contacts: $e'),
            backgroundColor: AppTheme.negativeRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF111827) : Colors.white;
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final primaryColor = Theme.of(context).colorScheme.primary;

    final peopleProvider = context.watch<PeopleProvider>();
    final isLoading = peopleProvider.isContactsLoading;
    final hasPermission = peopleProvider.hasContactPermission;
    final allContacts = peopleProvider.deviceContacts;
    final existingPeople = peopleProvider.people;

    final filteredContacts = allContacts.where((c) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final matchesName = c.displayName.toLowerCase().contains(q);
      final matchesPhone = c.phoneNumbers.any((p) => p.contains(q));
      return matchesName || matchesPhone;
    }).toList();

    final allFilteredKeys = filteredContacts.map(_getContactKey).toSet();
    final areAllFilteredSelected =
        filteredContacts.isNotEmpty && _selectedKeys.containsAll(allFilteredKeys);

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: isDark ? AppTheme.darkBorderSubtle : AppTheme.borderSubtle,
            width: 1.2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkBorderSubtle : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add From Contacts',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Select multiple contacts to import into Friends',
                        style: TextStyle(
                          fontSize: 12,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop('manual'),
                  icon: const Icon(Icons.edit_note_rounded, size: 20),
                  label: const Text('Manual Entry'),
                  style: TextButton.styleFrom(
                    foregroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search contacts by name or number...',
                hintStyle: TextStyle(color: textSecondary, fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded, color: textSecondary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded, color: textSecondary, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? AppTheme.darkSurfaceElevated.withValues(alpha: 0.7)
                    : const Color(0xFFF1F5F9),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark ? AppTheme.darkBorderUltraSubtle : AppTheme.borderSubtle,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark ? AppTheme.darkBorderUltraSubtle : AppTheme.borderSubtle,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: primaryColor, width: 1.5),
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),
          const SizedBox(height: 10),

          // Select All / Deselect All Bar (if contacts are loaded)
          if (!isLoading && hasPermission && filteredContacts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    '${filteredContacts.length} contacts found',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: textSecondary,
                    ),
                  ),
                  if (_selectedKeys.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_selectedKeys.length} selected',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _toggleSelectAll(filteredContacts),
                    icon: Icon(
                      areAllFilteredSelected
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                      size: 16,
                      color: primaryColor,
                    ),
                    label: Text(
                      areAllFilteredSelected ? 'Deselect All' : 'Select All',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 4),

          // Contact List Content
          Expanded(
            child: _buildContactContent(
              context: context,
              isLoading: isLoading,
              hasPermission: hasPermission,
              contacts: filteredContacts,
              existingPeople: existingPeople,
            ),
          ),

          // Sticky Bottom Bar for Multiple Selection Import
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: BoxDecoration(
              color: cardBg,
              border: Border(
                top: BorderSide(
                  color: isDark ? AppTheme.darkBorderUltraSubtle : AppTheme.borderSubtle,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  if (_selectedKeys.isNotEmpty) ...[
                    OutlinedButton(
                      onPressed: _isImporting
                          ? null
                          : () {
                              setState(() => _selectedKeys.clear());
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textSecondary,
                        side: BorderSide(
                          color: isDark ? AppTheme.darkBorderSubtle : AppTheme.borderSubtle,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Clear'),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_selectedKeys.isEmpty || _isImporting)
                          ? null
                          : () => _handleImportSelected(allContacts),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: isDark
                            ? Colors.white10
                            : const Color(0xFFE2E8F0),
                        disabledForegroundColor: isDark
                            ? Colors.white30
                            : const Color(0xFF94A3B8),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: _selectedKeys.isNotEmpty ? 2 : 0,
                      ),
                      icon: _isImporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Icon(Icons.person_add_alt_1_rounded, size: 20),
                      label: Text(
                        _selectedKeys.isEmpty
                            ? 'Select Contacts to Add'
                            : 'Add ${_selectedKeys.length} Contact${_selectedKeys.length > 1 ? "s" : ""} to Friends',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactContent({
    required BuildContext context,
    required bool isLoading,
    required bool hasPermission,
    required List<DeviceContactItem> contacts,
    required List<PersonModel> existingPeople,
  }) {
    final textSecondary = AppTheme.textSecondary(context);
    final textPrimary = AppTheme.textPrimary(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 2.8, color: primaryColor),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading contacts from device...',
              style: TextStyle(color: textSecondary, fontSize: 13.5),
            ),
          ],
        ),
      );
    }

    if (!hasPermission) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.contacts_rounded,
                size: 64,
                color: isDark ? AppTheme.darkBorderSubtle : Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'Contacts Permission Required',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'To easily import friends, allow FairShare access to your contacts. Or you can enter mobile numbers manually.',
                textAlign: TextAlign.center,
                style: TextStyle(color: textSecondary, height: 1.35, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  context.read<PeopleProvider>().loadDeviceContacts();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.lock_open_rounded, size: 18),
                label: const Text('Grant Permission', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop('manual'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: textPrimary,
                  side: BorderSide(color: isDark ? AppTheme.darkBorderSubtle : AppTheme.borderSubtle),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.dialpad_rounded, size: 18),
                label: const Text('Enter Mobile Number Manually'),
              ),
            ],
          ),
        ),
      );
    }

    if (contacts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 56,
                color: isDark ? AppTheme.darkBorderSubtle : Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isEmpty ? 'No contacts found' : 'No contacts matching "$_searchQuery"',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop('manual'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.person_add_rounded, size: 18),
                label: const Text('Add Person Manually', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 20),
      itemCount: contacts.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        indent: 72,
        color: isDark ? AppTheme.darkBorderUltraSubtle : AppTheme.borderSubtle,
      ),
      itemBuilder: (context, index) {
        final contact = contacts[index];
        final key = _getContactKey(contact);
        final isSelected = _selectedKeys.contains(key);
        final isAlreadyInFriends = _isAlreadyAdded(contact, existingPeople);
        final phone = contact.phoneNumbers.isNotEmpty
            ? contact.phoneNumbers.first
            : 'No phone number';

        return InkWell(
          onTap: () => _toggleContact(contact),
          child: Container(
            color: isSelected
                ? (isDark
                    ? primaryColor.withValues(alpha: 0.16)
                    : primaryColor.withValues(alpha: 0.08))
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                // Selection Checkbox / Toggle Indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? primaryColor : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? primaryColor
                          : (isDark ? AppTheme.darkBorderSubtle : Colors.grey.shade400),
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 14),

                // Avatar
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AvatarHelper.getColorForName(contact.displayName),
                  child: Text(
                    AvatarHelper.getInitials(contact.displayName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Details (Name, Phone)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              contact.displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14.5,
                                color: textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isAlreadyInFriends) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF064E3B)
                                    : const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_rounded,
                                    size: 11,
                                    color: isDark
                                        ? const Color(0xFF34D399)
                                        : const Color(0xFF059669),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Friend',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? const Color(0xFF34D399)
                                          : const Color(0xFF059669),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        phone,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 12.5,
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
    );
  }
}
