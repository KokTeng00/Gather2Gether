import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/constants/event_categories.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/core/validation/validators.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/places/data/place_repository.dart';
import 'package:gather2gether/features/places/domain/place_suggestion.dart';
import 'package:gather2gether/features/places/presentation/place_autocomplete_field.dart';
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
  const CreateEventScreen({
    required this.onCreated,
    this.placeRepository,
    this.eventRepository,
    this.initialEvent,
    this.templateEvent,
    super.key,
  }) : assert(initialEvent == null || templateEvent == null);

  final VoidCallback onCreated;
  final PlaceRepository? placeRepository;
  final EventRepository? eventRepository;
  final EventSummary? initialEvent;
  final EventSummary? templateEvent;

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _venueController;
  late final TextEditingController _addressController;
  late final TextEditingController _limitController;
  late final TextEditingController _languageController;
  late final TextEditingController _whatToBringController;
  late final EventRepository _events;
  late final PlaceRepository _places;

  String _category = eventCategories.first;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 20, minute: 0);
  double? _latitude;
  double? _longitude;
  bool _addressMatched = false;
  bool _submitting = false;
  bool _beginnerFriendly = false;
  bool _wheelchairAccessible = false;
  String _eventSetting = 'Not specified';
  String _ageGuidance = 'All ages';

  @override
  void initState() {
    super.initState();
    final event = widget.initialEvent ?? widget.templateEvent;
    _titleController = TextEditingController(text: event?.title);
    _descriptionController = TextEditingController(text: event?.description);
    _venueController = TextEditingController(text: event?.venueName);
    _addressController = TextEditingController(text: event?.address);
    _limitController = TextEditingController(
      text: event?.maxParticipants.toString() ?? '12',
    );
    _languageController = TextEditingController(text: event?.eventLanguage);
    _whatToBringController = TextEditingController(text: event?.whatToBring);
    _events = widget.eventRepository ?? EventRepository();
    _places = widget.placeRepository ?? PlaceRepository();
    if (event != null) {
      _category = event.category;
      var start = event.startAt;
      var end = event.endAt;
      if (widget.templateEvent != null) {
        final duration = end.difference(start);
        while (!start.isAfter(DateTime.now().add(const Duration(hours: 1)))) {
          start = start.add(const Duration(days: 7));
        }
        end = start.add(duration);
      }
      _date = start;
      _startTime = TimeOfDay.fromDateTime(start);
      _endTime = TimeOfDay.fromDateTime(end);
      _latitude = event.latitude;
      _longitude = event.longitude;
      _addressMatched = true;
      _beginnerFriendly = event.beginnerFriendly;
      _wheelchairAccessible = event.wheelchairAccessible;
      _eventSetting = switch (event.eventSetting) {
        'indoor' => 'Indoor',
        'outdoor' => 'Outdoor',
        'mixed' => 'Mixed',
        _ => 'Not specified',
      };
      _ageGuidance = switch (event.ageGuidance) {
        'families' => 'Family friendly',
        'teens' => 'Teens',
        'adults' => 'Adults only',
        _ => 'All ages',
      };
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _venueController.dispose();
    _addressController.dispose();
    _limitController.dispose();
    _languageController.dispose();
    _whatToBringController.dispose();
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

  void _onAddressChanged() {
    if (_latitude == null && _longitude == null && !_addressMatched) return;
    setState(() {
      _latitude = null;
      _longitude = null;
      _addressMatched = false;
    });
  }

  void _selectPlace(PlaceSuggestion place) {
    setState(() {
      _latitude = place.latitude;
      _longitude = place.longitude;
      _addressMatched = true;
      final venueName = place.suggestedVenueName;
      if (_venueController.text.trim().isEmpty && venueName != null) {
        _venueController.text = venueName;
      }
    });
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
      final input = CreateEventInput(
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
        beginnerFriendly: _beginnerFriendly,
        wheelchairAccessible: _wheelchairAccessible,
        eventSetting: switch (_eventSetting) {
          'Indoor' => 'indoor',
          'Outdoor' => 'outdoor',
          'Mixed' => 'mixed',
          _ => 'unspecified',
        },
        eventLanguage: _languageController.text,
        ageGuidance: switch (_ageGuidance) {
          'Family friendly' => 'families',
          'Teens' => 'teens',
          'Adults only' => 'adults',
          _ => 'all_ages',
        },
        whatToBring: _whatToBringController.text,
      );
      final event = widget.initialEvent;
      if (event == null) {
        await _events.createEvent(input);
      } else {
        await _events.updateEvent(event.id, input);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(event == null ? 'Event published.' : 'Event updated.'),
        ),
      );
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
        title: Text(
          widget.initialEvent != null
              ? 'Edit Event'
              : widget.templateEvent != null
              ? 'Create Again'
              : 'New Event',
        ),
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
                widget.initialEvent != null
                    ? 'Update the plan'
                    : widget.templateEvent != null
                    ? 'Run it again'
                    : 'Make a plan',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 6),
              Text(
                widget.initialEvent != null
                    ? 'Attendees will receive an in-app update when you save.'
                    : widget.templateEvent != null
                    ? 'The previous details are ready. Check the new date and publish.'
                    : 'Add the essentials. People can join as soon as you publish.',
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
                    AppChoiceField(
                      key: const Key('event-category-field'),
                      value: _category,
                      options: eventCategories,
                      enabled: !_submitting,
                      onChanged: (value) => setState(() => _category = value),
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
                    'Choose a suggested address so its global map pin matches.',
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
                    PlaceAutocompleteField(
                      controller: _addressController,
                      repository: _places,
                      latitude: _latitude,
                      longitude: _longitude,
                      enabled: !_submitting,
                      onTextChanged: _onAddressChanged,
                      onSelected: _selectPlace,
                      validator: (value) => Validators.requiredText(
                        value,
                        minLength: 3,
                        maxLength: 300,
                      ),
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
                title: 'Good to know',
                footer:
                    'These details help people quickly decide whether the event works for them.',
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      key: const Key('event-beginner-friendly'),
                      value: _beginnerFriendly,
                      onChanged: _submitting
                          ? null
                          : (value) =>
                                setState(() => _beginnerFriendly = value),
                      secondary: const Icon(CupertinoIcons.hand_thumbsup),
                      title: const Text('Beginner-friendly'),
                    ),
                    const Divider(indent: 52),
                    SwitchListTile.adaptive(
                      key: const Key('event-wheelchair-accessible'),
                      value: _wheelchairAccessible,
                      onChanged: _submitting
                          ? null
                          : (value) =>
                                setState(() => _wheelchairAccessible = value),
                      secondary: const Icon(CupertinoIcons.person_crop_circle),
                      title: const Text('Wheelchair accessible'),
                    ),
                    const Divider(indent: 52),
                    AppChoiceField(
                      key: const Key('event-setting-field'),
                      value: _eventSetting,
                      options: const [
                        'Not specified',
                        'Indoor',
                        'Outdoor',
                        'Mixed',
                      ],
                      label: 'Setting',
                      enabled: !_submitting,
                      onChanged: (value) =>
                          setState(() => _eventSetting = value),
                    ),
                    const Divider(indent: 52),
                    AppChoiceField(
                      key: const Key('event-age-guidance-field'),
                      value: _ageGuidance,
                      options: const [
                        'All ages',
                        'Family friendly',
                        'Teens',
                        'Adults only',
                      ],
                      label: 'Age group',
                      enabled: !_submitting,
                      onChanged: (value) =>
                          setState(() => _ageGuidance = value),
                    ),
                    const Divider(indent: 52),
                    TextFormField(
                      key: const Key('event-language-field'),
                      controller: _languageController,
                      maxLength: 80,
                      decoration: _fieldDecoration(
                        'Language (optional)',
                        CupertinoIcons.globe,
                      ).copyWith(counterText: ''),
                      validator: (value) => (value?.trim().length ?? 0) > 80
                          ? 'Use 80 characters or fewer.'
                          : null,
                    ),
                    const Divider(indent: 52),
                    TextFormField(
                      key: const Key('event-what-to-bring-field'),
                      controller: _whatToBringController,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: _fieldDecoration(
                        'What to bring (optional)',
                        CupertinoIcons.bag,
                      ).copyWith(counterText: ''),
                      validator: (value) => (value?.trim().length ?? 0) > 500
                          ? 'Use 500 characters or fewer.'
                          : null,
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
                    ? CupertinoActivityIndicator(
                        color: Theme.of(context).colorScheme.onPrimary,
                      )
                    : const Icon(CupertinoIcons.paperplane_fill),
                label: Text(
                  _submitting
                      ? (widget.initialEvent == null
                            ? 'Publishing…'
                            : 'Saving…')
                      : (widget.initialEvent == null
                            ? 'Publish Free Event'
                            : 'Save Changes'),
                ),
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
    this.trailingText,
  });

  final IconData icon;
  final String title;
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
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          if (trailingText != null)
            Text(
              trailingText!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
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
