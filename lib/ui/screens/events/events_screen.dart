import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/fair_share_logo.dart';
import '../../providers/auth_provider.dart';
import '../../providers/backup_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/event_provider.dart';
import '../../providers/expense_provider.dart';
import '../../providers/people_provider.dart';
import '../../providers/trip_sync_provider.dart';
import '../auth/widgets/user_profile_sheet.dart';
import '../categories/manage_categories_screen.dart';
import '../people/people_screen.dart';
import 'add_event_screen.dart';
import 'event_detail_screen.dart';
import 'widgets/event_card.dart';
class EventsScreen extends StatefulWidget {
  final bool isTab;
  const EventsScreen({super.key, this.isTab = false});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  String _selectedFilter = 'All';
  String _selectedTab = 'active'; // 'active', 'planning', 'history'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PeopleProvider>().initialize();
      context.read<EventProvider>().loadEvents();
    });
  }

  @override
  Widget build(BuildContext context) {
    final eventProvider = context.watch<EventProvider>();
    final categoryProvider = context.watch<CategoryProvider>();
    final authProvider = context.watch<AuthProvider>();
    final backupProvider = context.watch<BackupProvider>();
    final allEvents = eventProvider.events;
    final activeEvents = eventProvider.events.where((e) => e.status == 'active' && !e.isArchived).toList();
    final planningEvents = eventProvider.planningEvents;
    final archivedEvents = eventProvider.archivedEvents;
    
    final currentList = _selectedTab == 'planning'
        ? planningEvents
        : (_selectedTab == 'history' ? archivedEvents : activeEvents);
    final summaries = eventProvider.summaries;
    final isLoading = eventProvider.isLoading;

    final eventCategoryNames = categoryProvider.eventCategories.isNotEmpty
        ? categoryProvider.eventCategories.map((c) => c.name).toList()
        : EventCategories.all;
    final filterOptions = ['All', ...eventCategoryNames];
    final filteredEvents = _selectedFilter == 'All'
        ? currentList
        : currentList.where((e) => e.eventType == _selectedFilter).toList();

    final currentUser = authProvider.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            const FairShareLogo(size: 26, showGlow: true),
            const SizedBox(width: 10),
            Text(
              'FairShare',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 21,
                letterSpacing: -0.4,
                color: textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          if (!widget.isTab) ...[
            IconButton(
              icon: const Icon(Icons.category_rounded),
              tooltip: 'Manage Categories',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => const ManageCategoriesScreen(),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.people_alt_rounded),
              tooltip: 'Friends & Contacts',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => const PeopleScreen(),
                  ),
                );
              },
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FilledButton.icon(
              onPressed: () async {
                final eventProvider = context.read<EventProvider>();
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (ctx) => const AddEventScreen()),
                );
                if (mounted) {
                  eventProvider.loadEvents();
                }
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'New Split',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: backupProvider.isBackingUp
                ? 'Backing up data...'
                : (backupProvider.isFullyBackedUp
                    ? 'All details backed up'
                    : 'Details not backed up yet'),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                currentUser?.photoUrl != null && currentUser!.photoUrl!.isNotEmpty
                    ? CircleAvatar(
                        radius: 14,
                        backgroundImage: NetworkImage(currentUser.photoUrl!),
                      )
                    : CircleAvatar(
                        radius: 14,
                        backgroundColor: primaryColor.withValues(alpha: 0.15),
                        child: Text(
                          currentUser?.displayName.isNotEmpty == true
                              ? currentUser!.displayName[0].toUpperCase()
                              : 'U',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      ),
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      shape: BoxShape.circle,
                    ),
                    child: backupProvider.isBackingUp
                        ? const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              valueColor:
                                  AlwaysStoppedAnimation(Color(0xFF2563EB)),
                            ),
                          )
                        : Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: backupProvider.isFullyBackedUp
                                  ? const Color(0xFF10B981)
                                  : Colors.orange.shade800,
                            ),
                            child: Icon(
                              backupProvider.isFullyBackedUp
                                  ? Icons.check
                                  : Icons.priority_high_rounded,
                              size: 7,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
            onPressed: () => UserProfileSheet.show(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isLoading && allEvents.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                final eventProv = context.read<EventProvider>();
                final expenseProv = context.read<ExpenseProvider>();
                final tripSync = context.read<TripSyncProvider>();
                await eventProv.loadEvents();
                final sharedEvents = eventProv.events.where(
                  (e) => e.isShared || (e.driveFileId != null && e.driveFileId!.isNotEmpty),
                ).toList();
                for (final sharedEvent in sharedEvents) {
                  await tripSync.syncTrip(sharedEvent, eventProvider: eventProv, expenseProvider: expenseProv);
                }
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  // Minimal 3-way Segmented Toggle (Active vs Planning vs History)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkSurface : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? AppTheme.darkBorderUltraSubtle : AppTheme.borderSubtle,
                        width: 0.9,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Active
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _selectedTab = 'active'),
                            borderRadius: BorderRadius.circular(9),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              decoration: BoxDecoration(
                                color: _selectedTab == 'active'
                                    ? (isDark ? AppTheme.darkSurfaceElevated : Colors.white)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(9),
                                border: _selectedTab == 'active'
                                    ? Border.all(
                                        color: isDark ? AppTheme.darkBorderSubtle : AppTheme.borderSubtle,
                                        width: 0.9,
                                      )
                                    : null,
                                boxShadow: _selectedTab == 'active'
                                    ? [
                                        BoxShadow(
                                          color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.06),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1.5),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.bolt_rounded,
                                    size: 14,
                                    color: _selectedTab == 'active' ? primaryColor : textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Active (${activeEvents.length})',
                                    style: TextStyle(
                                      fontWeight: _selectedTab == 'active' ? FontWeight.w600 : FontWeight.w500,
                                      fontSize: 11.5,
                                      letterSpacing: -0.1,
                                      color: _selectedTab == 'active' ? primaryColor : textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Planning
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _selectedTab = 'planning'),
                            borderRadius: BorderRadius.circular(9),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              decoration: BoxDecoration(
                                color: _selectedTab == 'planning'
                                    ? (isDark ? AppTheme.darkSurfaceElevated : Colors.white)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(9),
                                border: _selectedTab == 'planning'
                                    ? Border.all(
                                        color: isDark ? AppTheme.darkBorderSubtle : AppTheme.borderSubtle,
                                        width: 0.9,
                                      )
                                    : null,
                                boxShadow: _selectedTab == 'planning'
                                    ? [
                                        BoxShadow(
                                          color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.06),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1.5),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.flight_takeoff_rounded,
                                    size: 14,
                                    color: _selectedTab == 'planning' ? const Color(0xFF2563EB) : textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Plan (${planningEvents.length})',
                                    style: TextStyle(
                                      fontWeight: _selectedTab == 'planning' ? FontWeight.w600 : FontWeight.w500,
                                      fontSize: 11.5,
                                      letterSpacing: -0.1,
                                      color: _selectedTab == 'planning' ? const Color(0xFF2563EB) : textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // History
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _selectedTab = 'history'),
                            borderRadius: BorderRadius.circular(9),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              decoration: BoxDecoration(
                                color: _selectedTab == 'history'
                                    ? (isDark ? AppTheme.darkSurfaceElevated : Colors.white)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(9),
                                border: _selectedTab == 'history'
                                    ? Border.all(
                                        color: isDark ? AppTheme.darkBorderSubtle : AppTheme.borderSubtle,
                                        width: 0.9,
                                      )
                                    : null,
                                boxShadow: _selectedTab == 'history'
                                    ? [
                                        BoxShadow(
                                          color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.06),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1.5),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.history_rounded,
                                    size: 14,
                                    color: _selectedTab == 'history' ? AppTheme.positiveGreen : textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'History (${archivedEvents.length})',
                                    style: TextStyle(
                                      fontWeight: _selectedTab == 'history' ? FontWeight.w600 : FontWeight.w500,
                                      fontSize: 11.5,
                                      letterSpacing: -0.1,
                                      color: _selectedTab == 'history' ? AppTheme.positiveGreen : textSecondary,
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

                  // Category Filter Chips
                  SizedBox(
                    height: 32,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: filterOptions.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        final filter = filterOptions[index];
                        final isSelected = filter == _selectedFilter;
                        return InkWell(
                          onTap: () => setState(() => _selectedFilter = filter),
                          borderRadius: BorderRadius.circular(8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? primaryColor
                                  : (isDark ? AppTheme.darkSurface : const Color(0xFFF8FAFC)),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? primaryColor
                                    : (isDark ? AppTheme.darkBorderSubtle : AppTheme.borderSubtle),
                                width: 0.9,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                filter,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : textSecondary,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Events list
                  if (filteredEvents.isEmpty)
                    _buildEmptyState(context)
                  else
                    ...filteredEvents.map((event) {
                      return EventCard(
                        event: event,
                        summary: summaries[event.id],
                        onTap: () async {
                          final eventProvider = context.read<EventProvider>();
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (ctx) => EventDetailScreen(eventId: event.id),
                            ),
                          );
                          if (mounted) {
                            eventProvider.loadEvents();
                          }
                        },
                      );
                    }),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);

    if (_selectedTab == 'history') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history_rounded, size: 56, color: textSecondary),
              const SizedBox(height: 16),
              Text(
                'No Completed Events Yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'When all debts in an event are cleared, tap "Split Complete" inside the event to archive it here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => setState(() => _selectedTab = 'active'),
                icon: const Icon(Icons.bolt_rounded, size: 16),
                label: const Text('View Active Splits'),
              ),
            ],
          ),
        ),
      );
    }

    if (_selectedTab == 'planning') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.flag_rounded, size: 56, color: textSecondary),
              const SizedBox(height: 16),
              Text(
                'No Planned Trips Yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'Plan upcoming trips with estimated budgets, installments, and committee pool tracking.',
                textAlign: TextAlign.center,
                style: TextStyle(color: textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () async {
                  final eventProvider = context.read<EventProvider>();
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (ctx) => const AddEventScreen()),
                  );
                  if (mounted) {
                    eventProvider.loadEvents();
                  }
                },
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Plan New Trip'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const FairShareLogo(size: 56, showGlow: true, useGlassContainer: true),
            const SizedBox(height: 16),
            Text(
              _selectedFilter == 'All'
                  ? 'No Splits Yet'
                  : 'No $_selectedFilter Splits',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              'Create a group for a Trip, Dinner, Rent, or Party to easily track and split expenses.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 22),
            Center(
              child: ElevatedButton.icon(
                onPressed: () async {
                  final eventProvider = context.read<EventProvider>();
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (ctx) => const AddEventScreen()),
                  );
                  if (mounted) {
                    eventProvider.loadEvents();
                  }
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Create Split'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
