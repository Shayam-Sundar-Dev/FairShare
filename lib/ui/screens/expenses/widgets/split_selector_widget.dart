import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/avatar_helper.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../data/models/person_model.dart';
import '../../../../domain/algorithms/split_calculator.dart';

class SplitSelectorWidget extends StatefulWidget {
  final double totalAmount;
  final String currency;
  final List<PersonModel> members;
  final SplitType initialSplitType;
  final List<String> initialSelectedIds;
  final Map<String, double> initialRawInputs;
  final Function(SplitType type, List<String> selectedIds, Map<String, double> rawInputs, bool isValid) onChanged;

  const SplitSelectorWidget({
    super.key,
    required this.totalAmount,
    this.currency = '₹',
    required this.members,
    this.initialSplitType = SplitType.equal,
    this.initialSelectedIds = const [],
    this.initialRawInputs = const {},
    required this.onChanged,
  });

  @override
  State<SplitSelectorWidget> createState() => _SplitSelectorWidgetState();
}

class _SplitSelectorWidgetState extends State<SplitSelectorWidget> {
  late SplitType _splitType;
  late Set<String> _selectedPersonIds;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, double> _rawInputs = {};
  String? _validationError;

  Map<String, int> get _memberCounts => {
    for (final m in widget.members) m.id: (m.count > 0 ? m.count : 1),
  };

  @override
  void initState() {
    super.initState();
    _splitType = widget.initialSplitType;
    _selectedPersonIds = widget.initialSelectedIds.isNotEmpty
        ? widget.initialSelectedIds.toSet()
        : widget.members.map((m) => m.id).toSet();

    _rawInputs.addAll(widget.initialRawInputs);
    _initControllers();
    final result = SplitCalculator.calculateSplits(
      expenseId: 'temp',
      totalAmount: widget.totalAmount,
      splitType: _splitType,
      selectedPersonIds: _selectedPersonIds.toList(),
      rawInputs: _rawInputs,
      personCounts: _memberCounts,
    );
    _validationError = result.isValid ? null : result.errorMessage;
  }

  void _initControllers() {
    for (final member in widget.members) {
      final existingVal = _rawInputs[member.id];
      final memberCount = member.count > 0 ? member.count : 1;
      final textVal = existingVal != null
          ? (existingVal % 1 == 0 ? existingVal.toInt().toString() : existingVal.toString())
          : (_splitType == SplitType.shares ? memberCount.toString() : '');
      _controllers[member.id] = TextEditingController(text: textVal);
      if (_splitType == SplitType.shares && existingVal == null) {
        _rawInputs[member.id] = memberCount.toDouble();
      }
    }
  }

  @override
  void didUpdateWidget(covariant SplitSelectorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.totalAmount != widget.totalAmount) {
      final result = SplitCalculator.calculateSplits(
        expenseId: 'temp',
        totalAmount: widget.totalAmount,
        splitType: _splitType,
        selectedPersonIds: _selectedPersonIds.toList(),
        rawInputs: _rawInputs,
        personCounts: _memberCounts,
      );
      _validationError = result.isValid ? null : result.errorMessage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onChanged(
            _splitType,
            _selectedPersonIds.toList(),
            _rawInputs,
            result.isValid,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _triggerRecalculation() {
    final result = SplitCalculator.calculateSplits(
      expenseId: 'temp',
      totalAmount: widget.totalAmount,
      splitType: _splitType,
      selectedPersonIds: _selectedPersonIds.toList(),
      rawInputs: _rawInputs,
      personCounts: _memberCounts,
    );

    setState(() {
      _validationError = result.isValid ? null : result.errorMessage;
    });

    widget.onChanged(
      _splitType,
      _selectedPersonIds.toList(),
      _rawInputs,
      result.isValid,
    );
  }

  void _onSplitTypeChanged(SplitType newType) {
    setState(() {
      _splitType = newType;
      _rawInputs.clear();

      final totalHeadcount = widget.members
          .where((m) => _selectedPersonIds.contains(m.id))
          .fold<int>(0, (sum, m) => sum + (m.count > 0 ? m.count : 1));

      for (final member in widget.members) {
        final memberCount = member.count > 0 ? member.count : 1;
        if (_splitType == SplitType.shares) {
          _rawInputs[member.id] = memberCount.toDouble();
          _controllers[member.id]?.text = memberCount.toString();
        } else if (_splitType == SplitType.percentage && totalHeadcount > 0) {
          if (_selectedPersonIds.contains(member.id)) {
            final pct = (100.0 * memberCount) / totalHeadcount;
            _rawInputs[member.id] = double.parse(pct.toStringAsFixed(1));
            _controllers[member.id]?.text = pct.toStringAsFixed(1);
          } else {
            _controllers[member.id]?.clear();
          }
        } else {
          _controllers[member.id]?.clear();
        }
      }
    });
    _triggerRecalculation();
  }

  @override
  Widget build(BuildContext context) {
    final selectedHeadcount = widget.members
        .where((m) => _selectedPersonIds.contains(m.id))
        .fold<int>(0, (sum, m) => sum + (m.count > 0 ? m.count : 1));
    final totalHeadcount = widget.members
        .fold<int>(0, (sum, m) => sum + (m.count > 0 ? m.count : 1));

        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Split Method',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<SplitType>(
              segments: const [
                ButtonSegment(value: SplitType.equal, label: Text('Equal')),
                ButtonSegment(value: SplitType.exact, label: Text('Exact')),
                ButtonSegment(value: SplitType.percentage, label: Text('%')),
                ButtonSegment(value: SplitType.shares, label: Text('Shares')),
              ],
              selected: {_splitType},
              onSelectionChanged: (set) => _onSplitTypeChanged(set.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  totalHeadcount > widget.members.length
                      ? 'Split between (${_selectedPersonIds.length}/${widget.members.length} • $selectedHeadcount/$totalHeadcount people)'
                      : 'Split between (${_selectedPersonIds.length}/${widget.members.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selectedPersonIds.length == widget.members.length) {
                        _selectedPersonIds.clear();
                      } else {
                        _selectedPersonIds = widget.members.map((m) => m.id).toSet();
                      }
                    });
                    _triggerRecalculation();
                  },
                  child: Text(
                    _selectedPersonIds.length == widget.members.length ? 'Deselect All' : 'Select All',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildMembersSplitList(),
            if (_validationError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.red.shade900.withValues(alpha: 0.25) : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? Colors.red.shade700.withValues(alpha: 0.5) : Colors.red.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: isDark ? Colors.red.shade300 : Colors.red,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _validationError!,
                        style: TextStyle(
                          color: isDark ? Colors.red.shade200 : Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      }

      Widget _buildMembersSplitList() {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primaryColor = Theme.of(context).colorScheme.primary;

        return Container(
          decoration: BoxDecoration(
            color: AppTheme.cardBg(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border(context)),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.members.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              indent: 56,
              color: isDark ? AppTheme.darkBorderUltraSubtle : const Color(0xFFF1F5F9),
            ),
            itemBuilder: (context, index) {
              final member = widget.members[index];
              final isSelected = _selectedPersonIds.contains(member.id);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Checkbox(
                      value: isSelected,
                      activeColor: primaryColor,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedPersonIds.add(member.id);
                          } else {
                            _selectedPersonIds.remove(member.id);
                          }
                        });
                        _triggerRecalculation();
                      },
                    ),
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AvatarHelper.getColorForName(member.name),
                      child: Text(
                        AvatarHelper.getInitials(member.name),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            member.isSelf ? '${member.name} (You)' : member.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: isSelected
                                  ? AppTheme.textPrimary(context)
                                  : AppTheme.textSecondary(context),
                            ),
                          ),
                          if (member.count > 1)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '${member.count} people',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: isSelected
                                      ? primaryColor
                                      : AppTheme.textSecondary(context),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isSelected) _buildSplitInputForMember(member),
                  ],
                ),
              );
            },
          ),
        );
      }

      Widget _buildSplitInputForMember(PersonModel member) {
        final primaryColor = Theme.of(context).colorScheme.primary;

        switch (_splitType) {
          case SplitType.equal:
            final memberCount = member.count > 0 ? member.count : 1;
            final totalHeadcount = widget.members
                .where((m) => _selectedPersonIds.contains(m.id))
                .fold<int>(0, (sum, m) => sum + (m.count > 0 ? m.count : 1));
            final perPerson = totalHeadcount > 0 ? (widget.totalAmount * memberCount / totalHeadcount) : 0.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  CurrencyFormatter.format(perPerson, symbol: widget.currency),
                  style: TextStyle(fontWeight: FontWeight.w600, color: primaryColor),
                ),
                if (memberCount > 1)
                  Text(
                    '($memberCount people)',
                    style: TextStyle(fontSize: 10, color: AppTheme.textSecondary(context), fontWeight: FontWeight.w500),
                  ),
              ],
            );

          case SplitType.exact:
            return SizedBox(
              width: 90,
              child: TextField(
                controller: _controllers[member.id],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: AppTheme.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  prefixText: widget.currency,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onChanged: (val) {
                  final amount = double.tryParse(val) ?? 0.0;
                  _rawInputs[member.id] = amount;
                  _triggerRecalculation();
                },
              ),
            );

          case SplitType.percentage:
            return SizedBox(
              width: 80,
              child: TextField(
                controller: _controllers[member.id],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: AppTheme.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                decoration: const InputDecoration(
                  suffixText: '%',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onChanged: (val) {
                  final pct = double.tryParse(val) ?? 0.0;
                  _rawInputs[member.id] = pct;
                  _triggerRecalculation();
                },
              ),
            );

          case SplitType.shares:
            final currentShare = _rawInputs[member.id] ?? 1.0;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: currentShare > 1
                      ? () {
                          final newVal = currentShare - 1;
                          setState(() {
                            _rawInputs[member.id] = newVal;
                            _controllers[member.id]?.text = newVal.toInt().toString();
                          });
                          _triggerRecalculation();
                        }
                      : null,
                ),
                Text(
                  '${currentShare.toInt()} ${currentShare == 1 ? "share" : "shares"}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final newVal = currentShare + 1;
                    setState(() {
                      _rawInputs[member.id] = newVal;
                      _controllers[member.id]?.text = newVal.toInt().toString();
                    });
                    _triggerRecalculation();
                  },
                ),
              ],
            );
        }
      }
    }
