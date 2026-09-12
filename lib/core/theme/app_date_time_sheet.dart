import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_sheet.dart';

class AppDateTimeSheet extends StatefulWidget {
  const AppDateTimeSheet({
    required this.title,
    required this.initialDateTime,
    required this.minimumDate,
    super.key,
  });

  final String title;
  final DateTime initialDateTime;
  final DateTime minimumDate;

  @override
  State<AppDateTimeSheet> createState() => _AppDateTimeSheetState();
}

class _AppDateTimeSheetState extends State<AppDateTimeSheet> {
  late DateTime _selected = widget.initialDateTime;

  @override
  Widget build(BuildContext context) => AppSheetScaffold(
    title: widget.title,
    bodyBuilder: (context, scrollController) => Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            physics: const ClampingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: SizedBox(
                height: 216,
                child: CupertinoDatePicker(
                  key: const Key('event-date-time-picker'),
                  mode: CupertinoDatePickerMode.dateAndTime,
                  initialDateTime: widget.initialDateTime,
                  minimumDate: widget.minimumDate,
                  use24hFormat: MediaQuery.alwaysUse24HourFormatOf(context),
                  onDateTimeChanged: (value) => _selected = value,
                ),
              ),
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
              key: const Key('use-event-date-time'),
              onPressed: () => Navigator.pop(context, _selected),
              child: const Text('Done'),
            ),
          ),
        ),
      ],
    ),
  );
}
