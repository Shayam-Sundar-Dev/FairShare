import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/avatar_helper.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/sync_time_formatter.dart';
import '../../../../core/widgets/liquid_glass.dart';
import '../../../../data/models/event_model.dart';
import '../../../../data/repositories/event_repository.dart';
import '../../../providers/category_provider.dart';
import 'trip_share_sheet.dart';

class EventCard extends StatelessWidget {
  final EventModel event;
  final EventSummaryData? summary;
  final VoidCallback onTap;

  const EventCard({
    super.key,
    required this.event,
    this.summary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final categoryProvider = context.watch<CategoryProvider>();
    final catColor = categoryProvider.getEventColor(event.eventType);
    final catIcon = categoryProvider.getEventIcon(event.eventType);
    final totalSpend = summary?.totalSpend ?? 0.0;
    final expenseCount = summary?.expenseCount ?? 0;
    final totalHeadcount = event.members.fold<int>(
      0,
      (sum, m) => sum + (m.count > 0 ? m.count : 1),
    );
    final effectiveCount = totalHeadcount > 0
        ? totalHeadcount
        : (event.members.isNotEmpty ? event.members.length : 1);
    final perPersonSpend = totalSpend / effectiveCount;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = AppTheme.border(context);
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return LiquidGlassContainer(
      margin: const EdgeInsets.only(bottom: 10),
      borderRadius: BorderRadius.circular(16),
      blur: 12,
      borderWidth: 0.9,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category icon with modern gradient tile
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            catColor.withValues(alpha: isDark ? 0.24 : 0.14),
                            catColor.withValues(alpha: isDark ? 0.10 : 0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: catColor.withValues(alpha: isDark ? 0.35 : 0.22),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: catColor.withValues(alpha: isDark ? 0.12 : 0.07),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(catIcon, color: catColor, size: 22),
                    ),
                    const SizedBox(width: 12),
                    // Title & category chips
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: catColor.withValues(alpha: isDark ? 0.15 : 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  event.eventType,
                                  style: TextStyle(
                                    color: catColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$expenseCount ${expenseCount == 1 ? "expense" : "expenses"}',
                                style: TextStyle(color: textSecondary, fontSize: 11.5),
                              ),
                              if (event.isPlanning) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E3A8A) : Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.flight_takeoff_rounded,
                                        size: 10,
                                        color: isDark ? const Color(0xFF60A5FA) : Colors.blue.shade700,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Planning',
                                        style: TextStyle(
                                          color: isDark ? const Color(0xFF60A5FA) : Colors.blue.shade700,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (event.isArchived) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF14532D) : Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 10,
                                        color: isDark ? const Color(0xFF4ADE80) : Colors.green.shade700,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Completed',
                                        style: TextStyle(
                                          color: isDark ? const Color(0xFF4ADE80) : Colors.green.shade700,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (event.isShared || (event.driveFileId != null && event.driveFileId!.isNotEmpty)) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF075985) : const Color(0xFFE0F2FE),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.add_to_drive_rounded,
                                        size: 10,
                                        color: isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0284C7),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Drive',
                                        style: TextStyle(
                                          color: isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0284C7),
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Total spend / Estimated Budget
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          CurrencyFormatter.format(
                            event.isPlanning && event.estimatedBudget > 0
                                ? event.estimatedBudget
                                : totalSpend,
                            symbol: event.currency,
                          ),
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: event.isPlanning ? const Color(0xFF2563EB) : primaryColor,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          event.isPlanning ? 'Est. Budget' : 'Total Spend',
                          style: TextStyle(fontSize: 10, color: textSecondary),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          event.isPlanning && event.estimatedBudget > 0
                              ? '${event.installmentsCount} ${(event.installmentsCount == 1 ? "installment" : "installments")}'
                              : '${CurrencyFormatter.format(perPersonSpend, symbol: event.currency)}/person',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: event.isPlanning ? const Color(0xFF2563EB) : textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: borderColor),
                const SizedBox(height: 10),
                // Members row
                Row(
                  children: [
                    _buildMemberAvatarStack(context, event),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        totalHeadcount > event.members.length
                            ? '${event.members.length} members ($totalHeadcount people)'
                            : '${event.members.length} ${event.members.length == 1 ? "person" : "people"}',
                        style: TextStyle(color: textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 1-Tap Share & Drive Sync button
                    InkWell(
                      onTap: () => TripShareSheet.show(context, event),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: (event.isShared || (event.driveFileId != null && event.driveFileId!.isNotEmpty))
                              ? (isDark ? const Color(0xFF075985) : const Color(0xFFE0F2FE))
                              : (isDark ? AppTheme.darkSurfaceElevated : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              (event.isShared || (event.driveFileId != null && event.driveFileId!.isNotEmpty))
                                  ? Icons.cloud_done_rounded
                                  : Icons.share_rounded,
                              size: 12,
                              color: (event.isShared || (event.driveFileId != null && event.driveFileId!.isNotEmpty))
                                  ? (isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0284C7))
                                  : textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              (event.isShared || (event.driveFileId != null && event.driveFileId!.isNotEmpty))
                                  ? SyncTimeFormatter.formatSyncTime(event.lastSyncedAt)
                                  : 'Share',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: (event.isShared || (event.driveFileId != null && event.driveFileId!.isNotEmpty))
                                    ? (isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0284C7))
                                    : textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios_rounded, size: 11, color: textSecondary.withValues(alpha: 0.6)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemberAvatarStack(BuildContext context, EventModel event) {
    final membersToShow = event.members.take(4).toList();
    final remaining = event.members.length - membersToShow.length;
    final cardBg = AppTheme.cardBg(context);

    return SizedBox(
      height: 24,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < membersToShow.length; i++)
            Align(
              widthFactor: 0.7,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: cardBg, width: 1.5),
                ),
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor: AvatarHelper.getColorForName(membersToShow[i].name),
                  child: Text(
                    AvatarHelper.getInitials(membersToShow[i].name),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          if (remaining > 0)
            Align(
              widthFactor: 0.7,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: cardBg, width: 1.5),
                ),
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor: AppTheme.slateLight,
                  child: Text(
                    '+$remaining',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
