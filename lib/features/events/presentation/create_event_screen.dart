import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/constants/event_categories.dart';
import 'package:gather2gether/core/location/location_service.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/core/validation/validators.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:intl/intl.dart';

String _publishErrorMessage(EdgeApiException error) => switch (error.code) {
  'authentication_required' ||
  'invalid_session' => 'Your session expired. Sign in again, then retry.',
  'event_validation' =>
    'Check that the event starts in the future and ends after it starts.',
  'invalid_parameter' || 'unexpected_fields' =>
    'One or more event details are invalid. Check the form and retry.',
  'authentication_unavailable' ||
  'database_unavailable' ||
  'edge_not_configured' =>
    'Publishing is temporarily unavailable. Please try again shortly.',
  _ => error.message,
};

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({required this.onCreated, super.key});

  final VoidCallback onCreated;

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _venueController = TextEditingController();
  final _addressController = TextEditingController();
  final _limitController = TextEditingController(text: '12');
  final _events = EventRepository();
  final _location = const LocationService();

  String _category = eventCategories.first;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 20, minute: 0);
  double? _latitude;
  double? _longitude;
  bool _loadingLocation = false;
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _venueController.dispose();
    _addressController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  DateTime _combine(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  Future<void> _pickDate() async {
    var selected = _date;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => _PickerSheet(
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          initialDateTime: _date,
          minimumDate: DateTime.now().subtract(const Duration(minutes: 1)),
          maximumDate: DateTime.now().add(const Duration(days: 365)),
          onDateTimeChanged: (value) => selected = value,
        ),
        onDone: () {
          setState(() => _date = selected);
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _pickTime({required bool start}) async {
    final original = start ? _startTime : _endTime;
    var selected = DateTime(2026, 1, 1, original.hour, original.minute);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => _PickerSheet(
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.time,
          use24hFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          initialDateTime: selected,
          minuteInterval: 5,
          onDateTimeChanged: (value) => selected = value,
        ),
        onDone: () {
          setState(() {
            final value = TimeOfDay.fromDateTime(selected);
            if (start) {
              _startTime = value;
            } else {
              _endTime = value;
            }
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _setCurrentLocation() async {
    setState(() => _loadingLocation = true);
    try {
      final position = await _location.currentPosition();
      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
      }
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          action: failure.canOpenSettings
              ? SnackBarAction(
                  label: 'Settings',
                  onPressed: _location.openSettings,
                )
              : null,
        ),
      );
    } catch (_) {
      _showError('Could not get the event location.');
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_latitude == null || _longitude == null) {
      _showError('Set the event location before publishing.');
      return;
    }
    final startAt = _combine(_date, _startTime);
    final endAt = _combine(_date, _endTime);
    if (!startAt.isAfter(DateTime.now())) {
      _showError('Start time must be in the future.');
      return;
    }
    if (!endAt.isAfter(startAt)) {
      _showError('End time must be after the start time.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      await _events.createEvent(
        CreateEventInput(
          title: _titleController.text,
          description: _descriptionController.text,
          category: _category,
          venueName: _venueController.text,
          address: _addressController.text,
          latitude: _latitude!,
          longitude: _longitude!,
          startAt: startAt,
          endAt: endAt,
          maxParticipants: int.parse(_limitController.text),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Event published.')));
      widget.onCreated();
    } on EdgeApiException catch (error) {
      _showError(_publishErrorMessage(error));
    } on TimeoutException {
      _showError('Publishing took too long. Check your connection and retry.');
    } catch (_) {
      _showError('Could not reach the publishing service. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _fieldDecoration(String hint, IconData icon) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Event'),
        leading: IconButton(
          tooltip: 'Close',
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          icon: const Icon(CupertinoIcons.xmark),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              Text(
                'Make a plan',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Add the essentials. People can join as soon as you publish.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              AppSection(
                title: 'About',
                child: Column(
                  children: [
                    TextFormField(
                      controller: _titleController,
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 120,
                      decoration: _fieldDecoration(
                        'Event title',
                        CupertinoIcons.sparkles,
                      ).copyWith(counterText: ''),
                      validator: (value) => Validators.requiredText(
                        value,
                        minLength: 3,
                        maxLength: 120,
                      ),
                    ),
                    const Divider(indent: 52),
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: _fieldDecoration(
                        'Category',
                        CupertinoIcons.square_grid_2x2,
                      ),
                      items: eventCategories
                          .map(
                            (category) => DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _category = value);
                      },
                    ),
                    const Divider(indent: 52),
                    TextFormField(
                      controller: _descriptionController,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 3,
                      maxLines: 7,
                      maxLength: 2000,
                      decoration: _fieldDecoration(
                        'What should people know?',
                        CupertinoIcons.text_alignleft,
                      ).copyWith(counterText: ''),
                      validator: (value) =>
                          Validators.requiredText(value, maxLength: 2000),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              AppSection(
                title: 'Where',
                footer:
                    'Your current position is used only to place the venue pin.',
                child: Column(
                  children: [
                    TextFormField(
                      controller: _venueController,
                      textCapitalization: TextCapitalization.words,
                      decoration: _fieldDecoration(
                        'Venue name',
                        CupertinoIcons.building_2_fill,
                      ),
                      validator: (value) => Validators.requiredText(
                        value,
                        minLength: 2,
                        maxLength: 160,
                      ),
                    ),
                    const Divider(indent: 52),
                    TextFormField(
                      controller: _addressController,
                      textCapitalization: TextCapitalization.words,
                      decoration: _fieldDecoration(
                        'Street address',
                        CupertinoIcons.map_pin_ellipse,
                      ),
                      validator: (value) => Validators.requiredText(
                        value,
                        minLength: 3,
                        maxLength: 300,
                      ),
                    ),
                    const Divider(indent: 52),
                    _ActionRow(
                      icon: _latitude == null
                          ? CupertinoIcons.location
                          : CupertinoIcons.location_fill,
                      title: _latitude == null
                          ? 'Set venue pin'
                          : 'Venue pin ready',
                      subtitle: _latitude == null
                          ? 'Use the simulator or phone location'
                          : 'Tap to update the position',
                      trailing: _loadingLocation
                          ? const CupertinoActivityIndicator()
                          : const Icon(
                              CupertinoIcons.chevron_forward,
                              size: 16,
                            ),
                      onTap: _loadingLocation ? null : _setCurrentLocation,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              AppSection(
                title: 'When',
                child: Column(
                  children: [
                    _ActionRow(
                      icon: CupertinoIcons.calendar,
                      title: 'Date',
                      trailingText: DateFormat('EEE, d MMM').format(_date),
                      onTap: _pickDate,
                    ),
                    const Divider(indent: 52),
                    _ActionRow(
                      icon: CupertinoIcons.clock,
                      title: 'Starts',
                      trailingText: _startTime.format(context),
                      onTap: () => _pickTime(start: true),
                    ),
                    const Divider(indent: 52),
                    _ActionRow(
                      icon: CupertinoIcons.clock_fill,
                      title: 'Ends',
                      trailingText: _endTime.format(context),
                      onTap: () => _pickTime(start: false),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              AppSection(
                title: 'Group size',
                footer: 'Choose between 2 and 500 people.',
                child: TextFormField(
                  controller: _limitController,
                  keyboardType: TextInputType.number,
                  decoration: _fieldDecoration(
                    'Participant limit',
                    CupertinoIcons.person_2,
                  ),
                  validator: Validators.participantLimit,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Icon(CupertinoIcons.paperplane_fill),
                label: Text(_submitting ? 'Publishing…' : 'Publish Free Event'),
              ),
              const SizedBox(height: 10),
              Text(
                'Every event on Gather2Gether is free.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.trailingText,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String? trailingText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (trailingText != null)
            Text(
              trailingText!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          ?trailing,
        ],
      ),
    ),
  );
}

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({required this.child, required this.onDone});

  final Widget child;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 320,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onDone, child: const Text('Done')),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}
