import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_sheet.dart';

/// A calendar that shares the scroll and drag behavior of the other app sheets.
class AppDateRangeSheet extends StatefulWidget {
  AppDateRangeSheet({
    required DateTime firstDate,
    required DateTime lastDate,
    DateTimeRange? initialDateRange,
    super.key,
  }) : firstDate = DateUtils.dateOnly(firstDate),
       lastDate = DateUtils.dateOnly(lastDate),
       initialDateRange = initialDateRange == null
           ? null
           : DateUtils.datesOnly(initialDateRange);

  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange? initialDateRange;

  @override
  State<AppDateRangeSheet> createState() => _AppDateRangeSheetState();
}

class _AppDateRangeSheetState extends State<AppDateRangeSheet> {
  late DateTime? _start = widget.initialDateRange?.start;
  late DateTime? _end = widget.initialDateRange?.end;
  bool _positioned = false;

  void _select(DateTime day) => setState(() {
    if (_start == null || _end != null || day.isBefore(_start!)) {
      _start = day;
      _end = null;
    } else {
      _end = day;
    }
  });

  String _summary(MaterialLocalizations localizations) {
    if (_start == null) return 'Choose a day, or two dates for a range.';
    final start = localizations.formatMediumDate(_start!);
    if (_end == null || _end == _start) return start;
    return '$start – ${localizations.formatMediumDate(_end!)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final dayHeight = math.max(44.0, textScaler.scale(14) + 20);
    final headingHeight = textScaler.scale(16) + 28;
    final weekdayHeight = textScaler.scale(12) + 16;
    final monthHeight = headingHeight + weekdayHeight + dayHeight * 6 + 12;
    final monthCount =
        DateUtils.monthDelta(widget.firstDate, widget.lastDate) + 1;

    return AppSheetScaffold(
      title: 'Choose dates',
      headerAction: TextButton(
        key: const Key('clear-calendar-dates'),
        onPressed: _start == null
            ? null
            : () => setState(() {
                _start = null;
                _end = null;
              }),
        child: const Text('Clear'),
      ),
      bodyBuilder: (context, scrollController) {
        if (!_positioned) {
          _positioned = true;
          final initialMonth = DateUtils.monthDelta(
            widget.firstDate,
            _start ?? widget.firstDate,
          ).clamp(0, monthCount - 1);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && scrollController!.hasClients) {
              scrollController.jumpTo(
                (initialMonth * monthHeight).clamp(
                  0.0,
                  scrollController.position.maxScrollExtent,
                ),
              );
            }
          });
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _summary(localizations),
                  key: const Key('calendar-range-summary'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                key: const Key('date-range-calendar'),
                controller: scrollController,
                physics: const ClampingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemExtent: monthHeight,
                itemCount: monthCount,
                itemBuilder: (context, index) => _month(
                  context,
                  DateTime(
                    widget.firstDate.year,
                    widget.firstDate.month + index,
                  ),
                  headingHeight: headingHeight,
                  weekdayHeight: weekdayHeight,
                  dayHeight: dayHeight,
                ),
              ),
            ),
            const Divider(height: 1),
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('use-calendar-dates'),
                  onPressed: _start == null
                      ? null
                      : () => Navigator.pop(
                          context,
                          DateTimeRange(start: _start!, end: _end ?? _start!),
                        ),
                  child: const Text('Use dates'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _month(
    BuildContext context,
    DateTime month, {
    required double headingHeight,
    required double weekdayHeight,
    required double dayHeight,
  }) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final offset = DateUtils.firstDayOffset(
      month.year,
      month.month,
      localizations,
    );
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: headingHeight,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              header: true,
              child: Text(
                localizations.formatMonthYear(month),
                style: theme.textTheme.titleSmall,
              ),
            ),
          ),
        ),
        SizedBox(
          height: weekdayHeight,
          child: Row(
            children: [
              for (var day = 0; day < 7; day++)
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      localizations.narrowWeekdays[(localizations
                                  .firstDayOfWeekIndex +
                              day) %
                          7],
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (var week = 0; week < 6; week++)
          SizedBox(
            height: dayHeight,
            child: Row(
              children: [
                for (var weekday = 0; weekday < 7; weekday++)
                  Expanded(
                    child:
                        week * 7 + weekday < offset ||
                            week * 7 + weekday >= offset + days
                        ? const SizedBox.shrink()
                        : _day(
                            context,
                            DateTime(
                              month.year,
                              month.month,
                              week * 7 + weekday - offset + 1,
                            ),
                          ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _day(BuildContext context, DateTime day) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final localizations = MaterialLocalizations.of(context);
    final enabled =
        !day.isBefore(widget.firstDate) && !day.isAfter(widget.lastDate);
    final endpoint = day == _start || day == _end;
    final inRange =
        _start != null &&
        _end != null &&
        !day.isBefore(_start!) &&
        !day.isAfter(_end!);
    final today = DateUtils.isSameDay(day, DateTime.now());
    return Semantics(
      button: true,
      enabled: enabled,
      selected: endpoint || inRange,
      onTap: enabled ? () => _select(day) : null,
      label: '${localizations.formatFullDate(day)}${today ? ', Today' : ''}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: inRange ? colors.primaryContainer : Colors.transparent,
              borderRadius: BorderRadiusDirectional.horizontal(
                start: day == _start ? const Radius.circular(24) : Radius.zero,
                end: day == _end ? const Radius.circular(24) : Radius.zero,
              ),
            ),
            child: Material(
              color: endpoint ? colors.primary : Colors.transparent,
              shape: CircleBorder(
                side: today && !endpoint
                    ? BorderSide(color: colors.primary)
                    : BorderSide.none,
              ),
              child: InkWell(
                key: ValueKey(
                  'calendar-day-${day.year}-${day.month}-${day.day}',
                ),
                customBorder: const CircleBorder(),
                onTap: enabled ? () => _select(day) : null,
                child: Center(
                  child: Text(
                    localizations.formatDecimal(day.day),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: !enabled
                          ? colors.onSurface.withValues(alpha: 0.3)
                          : endpoint
                          ? colors.onPrimary
                          : inRange
                          ? colors.onPrimaryContainer
                          : colors.onSurface,
                      fontWeight: endpoint ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
