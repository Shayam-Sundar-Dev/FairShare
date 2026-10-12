import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/avatar_helper.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../data/models/person_model.dart';
import '../../providers/people_provider.dart';
import 'add_person_dialog.dart';
import 'contact_picker_sheet.dart';

class PeopleScreen extends StatelessWidget {
  final bool isTab;
  const PeopleScreen({super.key, this.isTab = false});

  void _showAddOptions(BuildContext context) {
    final textPrimary = AppTheme.textPrimary(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkBorderSubtle : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text(
                  'Add Person to FairShare',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.contacts_rounded, color: Theme.of(context).colorScheme.primary),
                ),
                title: const Text('Add from Device Contacts', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Select single or multiple contacts at once'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ContactPickerSheet.show(context);
                },
              ),
              const Divider(indent: 64),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.positiveGreen.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.dialpad_rounded, color: AppTheme.positiveGreen),
                ),
                title: const Text('Add Manually (Name & Phone)', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Enter name and mobile number'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showDialog(
                    context: context,
                    builder: (dialogCtx) => const AddPersonDialog(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final peopleProvider = context.watch<PeopleProvider>();
    final people = peopleProvider.people;
    final isLoading = peopleProvider.isLoading;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: !isTab,
        title: const Text('Friends & Contacts'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FilledButton.icon(
              onPressed: () => _showAddOptions(context),
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: const Text(
                'Add Friend',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : people.isEmpty
              ? _buildEmptyState(context)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: people.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final person = people[index];
                    return _buildPersonTile(context, person);
                  },
                ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.group_outlined, size: 52, color: primaryColor),
            ),
            const SizedBox(height: 18),
            Text(
              'No Friends Added Yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              'Add friends from contacts or type mobile numbers to start splitting expenses.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAddOptions(context),
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: const Text('Add First Friend'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonTile(BuildContext context, PersonModel person) {
    final color = AvatarHelper.getColorForName(person.name);
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return LiquidGlassContainer(
      borderRadius: BorderRadius.circular(14),
      blur: 12,
      borderWidth: 0.9,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: color,
          child: Text(
            AvatarHelper.getInitials(person.name),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                person.name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                  letterSpacing: -0.2,
                  color: textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (person.isSelf) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  'YOU',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          person.phoneNumber.isNotEmpty ? person.phoneNumber : 'No phone number',
          style: TextStyle(fontSize: 11.5, color: textSecondary),
        ),
        trailing: person.isSelf
            ? null
            : Icon(Icons.arrow_forward_ios_rounded, size: 11, color: textSecondary.withValues(alpha: 0.6)),
      ),
    );
  }
}
