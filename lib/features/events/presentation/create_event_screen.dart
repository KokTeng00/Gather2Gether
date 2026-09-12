import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_sheet.dart';
import 'package:gather2gether/core/theme/app_date_time_sheet.dart';
import 'package:gather2gether/core/constants/event_categories.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/core/validation/validators.dart';
import 'package:gather2gether/features/assistant/data/assistant_repository.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/places/data/place_repository.dart';
import 'package:gather2gether/features/places/domain/place_suggestion.dart';
import 'package:gather2gether/features/places/presentation/place_autocomplete_field.dart';
import 'package:intl/intl.dart';
import 'package:gather2gether/core/media/app_image_picker.dart';
import 'package:gather2gether/core/media/prepared_image.dart';
import 'package:gather2gether/features/events/presentation/event_planning_widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

const _audiences = {
  'public': 'Public',
  'followers': 'My followers',
  'following': 'People I follow',
  'selected': 'Specific people',
  'unlisted': 'Unlisted · invite only',
};

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
    this.assistantRepository,
    this.initialEvent,
    this.templateEvent,
    this.editScope = 'this',
    this.asSheet = false,
    this.pollPostId,
    this.pollOptionId,
    super.key,
  }) : assert(initialEvent == null || templateEvent == null);

  final VoidCallback onCreated;
  final PlaceRepository? placeRepository;
  final EventRepository? eventRepository;
  final AssistantRepository? assistantRepository;
  final EventSummary? initialEvent;
  final EventSummary? templateEvent;
  final String editScope;
  final bool asSheet;
  final String? pollPostId;
  final String? pollOptionId;

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _meetingExpansion = ExpansibleController();
  final _guestsExpansion = ExpansibleController();
  final _detailsExpansion = ExpansibleController();
  final _sharingExpansion = ExpansibleController();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _venueController;
  late final TextEditingController _addressController;
  late final TextEditingController _limitController;
  late final TextEditingController _languageController;
  late final TextEditingController _whatToBringController;
  late final EventRepository _events;
  late final AssistantRepository _assistant;
  late final PlaceRepository _places;

  final _meetingInstructions = TextEditingController();
  final _previewArea = TextEditingController();
  final _audienceUsernames = TextEditingController();
  LatLng? _meetingPoint;
  PreparedImage? _meetingPhoto;
  bool _removeMeetingPhoto = false;
  bool _preparingPhoto = false;
  bool _allowGuest = false;
  bool _invitePreview = false;

  String _category = eventCategories.first;
  late DateTime _startAt;
  late DateTime _endAt;
  double? _latitude;
  double? _longitude;
  bool _addressMatched = false;
  bool _submitting = false;
  bool _generatingDraft = false;
  bool _beginnerFriendly = false;
  bool _wheelchairAccessible = false;
  String _eventSetting = 'Not specified';
  String _ageGuidance = 'All ages';
  String _visibility = 'Public';
  String _repeat = 'Does not repeat';

  bool get _restrictedAudience =>
      !['Public', 'Unlisted · invite only'].contains(_visibility);

  List<String> get _selectedUsernames => _audienceUsernames.text
      .split(RegExp(r'[,\s]+'))
      .where((name) => name.isNotEmpty)
      .map((name) => name.replaceFirst(RegExp(r'^@'), '').toLowerCase())
      .toSet()
      .toList();

  String get _audienceDescription => switch (_visibility) {
    'My followers' =>
      'Only people who follow you can discover and open this event. Hosts keep access.',
    'People I follow' =>
      'Only people you follow can discover and open this event. Hosts keep access.',
    'Specific people' =>
      'Only the usernames you enter can discover and open this event. Hosts keep access.',
    'Unlisted · invite only' =>
      'Only people with your invite link can open this event. It will not appear in Discover.',
    _ => 'Public events can appear in Discover and search alerts.',
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startAt = DateTime(now.year, now.month, now.day + 1, 18);
    _endAt = DateTime(now.year, now.month, now.day + 1, 20);
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
    _assistant = widget.assistantRepository ?? AssistantRepository();
    _places = widget.placeRepository ?? PlaceRepository();
    if (event != null) {
      _meetingInstructions.text = event.meetingInstructions;
      _previewArea.text = event.previewArea;
      _allowGuest = event.allowGuest;
      _invitePreview = event.invitePreviewEnabled;
      if (event.meetingLatitude != null && event.meetingLongitude != null) {
        _meetingPoint = LatLng(event.meetingLatitude!, event.meetingLongitude!);
      }
      _category = event.category;
      var start = event.startAt.toLocal();
      var end = event.endAt.toLocal();
      if (widget.templateEvent != null && widget.pollPostId == null) {
        final duration = end.difference(start);
        while (!start.isAfter(DateTime.now().add(const Duration(hours: 1)))) {
          start = start.add(const Duration(days: 7));
        }
        end = start.add(duration);
      }
      _startAt = start;
      _endAt = end;
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
      _visibility = _audiences[event.eventVisibility] ?? 'Public';
      _audienceUsernames.text = event.audienceUsernames
          .map((name) => '@$name')
          .join(', ');
      if (_restrictedAudience) _invitePreview = false;
    }
    if (widget.pollPostId != null) {
      _latitude = null;
      _longitude = null;
      _addressMatched = false;
      _visibility = 'Public';
    }
  }

  @override
  void dispose() {
    _meetingExpansion.dispose();
    _guestsExpansion.dispose();
    _detailsExpansion.dispose();
    _sharingExpansion.dispose();
    _meetingInstructions.dispose();
    _previewArea.dispose();
    _audienceUsernames.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _venueController.dispose();
    _addressController.dispose();
    _limitController.dispose();
    _languageController.dispose();
    _whatToBringController.dispose();
    super.dispose();
  }

  String _dateTimeLabel(DateTime value) =>
      '${DateFormat('EEE, d MMM').format(value)} · ${TimeOfDay.fromDateTime(value).format(context)}';

  Future<void> _pickDateTime({required bool start}) async {
    if (widget.pollPostId != null) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final original = start ? _startAt : _endAt;
    final earliest = start
        ? DateTime.now()
        : _startAt.add(const Duration(minutes: 1));
    final selected = await showAppSheet<DateTime>(
      context: context,
      builder: (_) => AppDateTimeSheet(
        title: start ? 'Starts' : 'Ends',
        initialDateTime: original,
        minimumDate: original.isBefore(earliest) ? original : earliest,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        final duration = _endAt.difference(_startAt);
        _startAt = selected;
        if (!_endAt.isAfter(_startAt)) {
          _endAt = _startAt.add(
            duration.isNegative || duration == Duration.zero
                ? const Duration(hours: 2)
                : duration,
          );
        }
      } else {
        _endAt = selected;
      }
    });
  }

  void _onAddressChanged() {
    if (_latitude == null && _longitude == null && !_addressMatched) return;
    setState(() {
      _venueController.clear();
      _latitude = null;
      _longitude = null;
      _addressMatched = false;
    });
  }

  void _selectPlace(PlaceSuggestion place) {
    setState(() {
      _latitude = place.latitude;
      _longitude = place.longitude;
      _meetingPoint = null;
      _addressMatched = true;
      var venueName = (place.suggestedVenueName ?? place.displayTitle).trim();
      if (venueName.length < 2) venueName = place.formattedAddress;
      _venueController.text = venueName.length > 160
          ? venueName.substring(0, 160)
          : venueName;
    });
  }

  Future<void> _draftWithAi() async {
    if (_generatingDraft || _submitting) return;
    final prompt = await showDialog<String>(
      context: context,
      builder: (_) => const _EventIdeaDialog(),
    );
    if (prompt == null || !mounted) return;
    setState(() => _generatingDraft = true);
    try {
      final draft = await _assistant.draftEvent(
        prompt: prompt,
        locale: Localizations.localeOf(context).toLanguageTag(),
      );
      if (!mounted) return;
      setState(() {
        _titleController.text = draft.title;
        _descriptionController.text = draft.description;
        _category = draft.category;
        _beginnerFriendly = draft.beginnerFriendly;
        _eventSetting = switch (draft.eventSetting) {
          'indoor' => 'Indoor',
          'outdoor' => 'Outdoor',
          'mixed' => 'Mixed',
          _ => 'Not specified',
        };
        _languageController.text = draft.eventLanguage;
        _ageGuidance = switch (draft.ageGuidance) {
          'families' => 'Family friendly',
          'teens' => 'Teens',
          'adults' => 'Adults only',
          _ => 'All ages',
        };
        _whatToBringController.text = draft.whatToBring;
      });
      _showError('Draft added. Review the details before publishing.');
    } on AssistantApiException catch (error) {
      _showError(error.message);
    } on TimeoutException {
      _showError('Drafting took too long. Please try again.');
    } catch (_) {
      _showError('Could not create a draft right now.');
    } finally {
      if (mounted) setState(() => _generatingDraft = false);
    }
  }

  Future<void> _submit({required bool publish}) async {
    if (_submitting || _preparingPhoto) return;
    final invalidFields = _formKey.currentState?.validateGranularly();
    if (invalidFields == null) return;
    if (invalidFields.isNotEmpty) {
      for (final field in invalidFields) {
        field.context
            .findAncestorWidgetOfExactType<_OptionalEventSection>()
            ?.controller
            .expand();
      }
      // Reveal errors inside collapsed sections before scrolling to the first one.
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted || !invalidFields.first.mounted) return;
      await Scrollable.ensureVisible(
        invalidFields.first.context,
        alignment: 0.15,
        duration: const Duration(milliseconds: 200),
      );
      return;
    }
    if (_latitude == null || _longitude == null) {
      _showError('Set the event location before saving.');
      return;
    }
    final startAt = _startAt;
    final endAt = _endAt;
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
      final input = _eventInput(
        publish: publish,
        startAt: startAt,
        endAt: endAt,
      );
      final event = widget.initialEvent;
      if (event == null) {
        if (_meetingPhoto == null) {
          await _events.createEvent(input);
        } else {
          await _events.createEventWithPhoto(input, photo: _meetingPhoto);
        }
      } else if (event.eventSeriesId != null && widget.editScope != 'this') {
        if (_meetingPhoto == null) {
          await _events.updateEventSeries(event.id, widget.editScope, input);
        } else {
          await _events.updateSeriesWithPhoto(
            event.id,
            widget.editScope,
            input,
            photo: _meetingPhoto,
          );
        }
      } else {
        if (_meetingPhoto == null) {
          await _events.updateEvent(event.id, input);
        } else {
          await _events.updateEventWithPhoto(
            event.id,
            input,
            photo: _meetingPhoto,
          );
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            publish
                ? (_repeat == 'Does not repeat' || event != null
                      ? 'Event published.'
                      : 'Event series published.')
                : (event == null ? 'Draft saved.' : 'Draft updated.'),
          ),
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

  CreateEventInput _eventInput({
    required bool publish,
    required DateTime startAt,
    required DateTime endAt,
  }) => CreateEventInput(
    title: _titleController.text,
    description: _descriptionController.text,
    category: _category,
    venueName: _venueController.text,
    address: _addressController.text,
    latitude: _latitude!,
    longitude: _longitude!,
    startAt: startAt,
    endAt: endAt,
    maxParticipants: int.tryParse(_limitController.text) ?? 2,
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
    meetingInstructions: _meetingInstructions.text,
    meetingLatitude: _meetingPoint?.latitude,
    meetingLongitude: _meetingPoint?.longitude,
    allowGuest: _allowGuest,
    invitePreviewEnabled: _invitePreview,
    previewArea: _previewArea.text,
    timezoneOffsetMinutes: startAt.timeZoneOffset.inMinutes,
    removeMeetingImage: _removeMeetingPhoto,
    pollPostId: widget.pollPostId,
    pollOptionId: widget.pollOptionId,
    whatToBring: _whatToBringController.text,
    status: publish ? 'published' : 'draft',
    visibility: _audiences.entries.firstWhere((e) => e.value == _visibility).key,
    audienceUsernames: _visibility == 'Specific people' ? _selectedUsernames : const [],
    repeatInterval: !publish || widget.initialEvent != null
        ? 'none'
        : switch (_repeat) {
            'Weekly · 4 events' => 'weekly',
            'Monthly · 3 events' => 'monthly',
            _ => 'none',
          },
    repeatCount: !publish || widget.initialEvent != null
        ? 1
        : switch (_repeat) {
            'Weekly · 4 events' => 4,
            'Monthly · 3 events' => 3,
            _ => 1,
          },
  );

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickMeetingPoint() async {
    if (_latitude == null || _longitude == null) {
      _showError('Choose the venue first.');
      return;
    }
    final point = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => MeetingPointPicker(
          initial: _meetingPoint ?? LatLng(_latitude!, _longitude!),
        ),
      ),
    );
    if (mounted && point != null) setState(() => _meetingPoint = point);
  }

  Future<void> _pickMeetingPhoto() async {
    final source = await showCupertinoModalPopup<AppImageSource>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Meeting photo'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, AppImageSource.gallery),
            child: const Text('Choose a photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, AppImageSource.camera),
            child: const Text('Take a photo'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (source == null || !mounted) return;
    setState(() => _preparingPhoto = true);
    try {
      final image = await AppImagePicker().pickImage(source);
      if (image != null && mounted) {
        setState(() {
          _meetingPhoto = image;
          _removeMeetingPhoto = false;
        });
      }
    } catch (_) {
      if (mounted) _showError('Could not open that photo. Try another one.');
    } finally {
      if (mounted) setState(() => _preparingPhoto = false);
    }
  }

  Widget _meetingSection() {
    final existingPhoto =
        widget.initialEvent?.hasMeetingImage == true && !_removeMeetingPhoto;
    return _OptionalEventSection(
      sectionKey: 'event-meeting-options',
      title: 'Meeting details',
      summary: _summary([
        if (_meetingInstructions.text.trim().isNotEmpty) 'Instructions added',
        if (_meetingPoint != null) 'Pin set',
        if (_meetingPhoto != null || existingPhoto) 'Photo added',
      ], 'Instructions, exact pin or entrance photo'),
      icon: CupertinoIcons.map_pin_ellipse,
      controller: _meetingExpansion,
      enabled: !_submitting,
      onExpansionChanged: (expanded) {
        if (!expanded) FocusScope.of(context).unfocus();
        setState(() {});
      },
      footer: 'A landmark or entrance makes the first hello easier.',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextFormField(
              key: const Key('event-meeting-instructions'),
              controller: _meetingInstructions,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              validator: (value) => (value?.trim().length ?? 0) > 500
                  ? 'Use 500 characters or fewer.'
                  : null,
              decoration: const InputDecoration(
                labelText: 'Finding the group',
                hintText:
                    'Meet beside the café entrance. I’ll have a blue backpack.',
              ),
            ),
          ),
          ListTile(
            key: const Key('event-meeting-pin'),
            leading: const Icon(CupertinoIcons.map_pin_ellipse),
            title: Text(
              _meetingPoint == null
                  ? 'Set an exact meeting point'
                  : 'Meeting point set',
            ),
            subtitle: Text(
              _meetingPoint == null
                  ? 'Optional · useful for parks and large venues'
                  : 'Tap to adjust the pin',
            ),
            trailing: _meetingPoint == null
                ? const Icon(CupertinoIcons.chevron_right, size: 16)
                : IconButton(
                    tooltip: 'Use venue location',
                    onPressed: _submitting
                        ? null
                        : () => setState(() => _meetingPoint = null),
                    icon: const Icon(CupertinoIcons.xmark_circle),
                  ),
            onTap: _submitting ? null : _pickMeetingPoint,
          ),
          if (_meetingExpansion.isExpanded &&
              (_meetingPhoto != null || existingPhoto))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _meetingPhoto != null
                    ? Image.memory(
                        _meetingPhoto!.bytes,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      )
                    : Image.network(
                        _events.meetingImageUrl(widget.initialEvent!.id),
                        headers: _events.mediaHeaders(),
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(
                          height: 60,
                          child: Center(
                            child: Text('Photo preview unavailable'),
                          ),
                        ),
                      ),
              ),
            ),
          ListTile(
            key: const Key('event-meeting-photo'),
            leading: const Icon(CupertinoIcons.camera),
            title: Text(
              _preparingPhoto
                  ? 'Opening photo…'
                  : _meetingPhoto != null || existingPhoto
                  ? 'Change meeting photo'
                  : 'Add an entrance photo',
            ),
            onTap: _submitting || _preparingPhoto ? null : _pickMeetingPhoto,
            trailing: _meetingPhoto != null || existingPhoto
                ? IconButton(
                    tooltip: 'Remove meeting photo',
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                            _meetingPhoto = null;
                            _removeMeetingPhoto = true;
                          }),
                    icon: const Icon(CupertinoIcons.trash, size: 19),
                  )
                : null,
          ),
        ],
      ),
    );
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
    return AppSheetScaffold(
      asSheet: widget.asSheet,
      canDismiss: !_submitting,
      title: widget.initialEvent != null
          ? 'Edit event'
          : widget.pollPostId != null
          ? 'Make it a plan'
          : widget.templateEvent != null
          ? 'Create again'
          : 'New event',
      bodyBuilder: (context, scrollController) => SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            controller: scrollController,
            physics: const ClampingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.initialEvent != null
                      ? 'Update the details below. Attendees will be notified when you save.'
                      : widget.templateEvent != null
                      ? 'The previous details are ready. Check the new date and publish.'
                      : 'Start with the basics. Add optional details if you need them.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                AppSection(
                  title: 'Basics',
                  action:
                      widget.initialEvent == null &&
                          widget.templateEvent == null
                      ? TextButton.icon(
                          key: const Key('event-ai-draft-button'),
                          onPressed: _generatingDraft || _submitting
                              ? null
                              : _draftWithAi,
                          style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: _generatingDraft
                              ? const CupertinoActivityIndicator(radius: 7)
                              : const Icon(CupertinoIcons.pencil, size: 17),
                          label: Text(
                            _generatingDraft ? 'Writing…' : 'Help me write',
                          ),
                        )
                      : null,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _titleController,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 120,
                        decoration: _fieldDecoration(
                          'Event title',
                          CupertinoIcons.textformat,
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
                  title: 'Location',
                  footer:
                      'Choose a suggested address so people can find the right place.',
                  child: PlaceAutocompleteField(
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
                ),
                const SizedBox(height: 24),
                AppSection(
                  title: 'Date and time',
                  footer: widget.pollPostId == null
                      ? null
                      : 'Using the date you chose from the poll. Everyone will confirm their own place.',
                  child: Column(
                    children: [
                      _ActionRow(
                        key: const Key('event-start-date-time'),
                        icon: CupertinoIcons.clock,
                        title: 'Starts',
                        trailingText: _dateTimeLabel(_startAt),
                        onTap: widget.pollPostId != null || _submitting
                            ? null
                            : () => _pickDateTime(start: true),
                      ),
                      const Divider(indent: 52),
                      _ActionRow(
                        key: const Key('event-end-date-time'),
                        icon: CupertinoIcons.clock_fill,
                        title: 'Ends',
                        trailingText: _dateTimeLabel(_endAt),
                        onTap: widget.pollPostId != null || _submitting
                            ? null
                            : () => _pickDateTime(start: false),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Optional details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap a section to add more.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _meetingSection(),
                const SizedBox(height: 10),
                _OptionalEventSection(
                  sectionKey: 'event-guests-options',
                  title: 'Guests & capacity',
                  summary:
                      '${int.tryParse(_limitController.text) == null ? 'Set a place limit' : '${_limitController.text} places'} · ${_allowGuest ? 'Friends welcome' : 'One place per person'}',
                  icon: CupertinoIcons.person_2,
                  controller: _guestsExpansion,
                  enabled: !_submitting,
                  onExpansionChanged: (expanded) {
                    if (!expanded) FocusScope.of(context).unfocus();
                    setState(() {});
                  },
                  footer: 'The place limit includes you and any extra friends.',
                  child: Column(
                    children: [
                      TextFormField(
                        key: const Key('event-capacity-field'),
                        controller: _limitController,
                        keyboardType: TextInputType.number,
                        decoration: _fieldDecoration(
                          'Maximum number of people',
                          CupertinoIcons.person_2,
                        ),
                        validator: Validators.participantLimit,
                      ),
                      const Divider(indent: 52),
                      SwitchListTile.adaptive(
                        key: const Key('event-allow-guest'),
                        value: _allowGuest,
                        onChanged: _submitting
                            ? null
                            : (value) => setState(() => _allowGuest = value),
                        title: const Text('Let people bring a friend'),
                        subtitle: const Text(
                          'One guest per member, included in the place limit.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _OptionalEventSection(
                  sectionKey: 'event-details-options',
                  title: 'More details',
                  summary: _summary([
                    if (_beginnerFriendly) 'Beginner-friendly',
                    if (_wheelchairAccessible) 'Wheelchair accessible',
                    if (_eventSetting != 'Not specified') _eventSetting,
                    if (_ageGuidance != 'All ages') _ageGuidance,
                    if (_languageController.text.trim().isNotEmpty)
                      _languageController.text.trim(),
                    if (_whatToBringController.text.trim().isNotEmpty)
                      'What to bring added',
                  ], 'Accessibility, language and what to bring'),
                  icon: CupertinoIcons.slider_horizontal_3,
                  controller: _detailsExpansion,
                  enabled: !_submitting,
                  onExpansionChanged: (expanded) {
                    if (!expanded) FocusScope.of(context).unfocus();
                    setState(() {});
                  },
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
                        secondary: const Icon(
                          CupertinoIcons.person_crop_circle,
                        ),
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
                const SizedBox(height: 10),
                _OptionalEventSection(
                  sectionKey: 'event-sharing-options',
                  title: 'Sharing & repeat',
                  summary:
                      '$_visibility · ${_repeat == 'Does not repeat' ? 'Single event' : _repeat} · ${_invitePreview ? 'Preview on' : 'Preview off'}',
                  icon: CupertinoIcons.link,
                  controller: _sharingExpansion,
                  enabled: !_submitting,
                  onExpansionChanged: (expanded) {
                    if (!expanded) FocusScope.of(context).unfocus();
                    setState(() {});
                  },
                  footer: _audienceDescription,
                  child: Column(
                    children: [
                      AppChoiceField(
                        key: const Key('event-visibility-field'),
                        value: _visibility,
                        options: _audiences.values.toList(),
                        label: 'Who can see this event',
                        enabled: !_submitting && widget.pollPostId == null,
                        onChanged: (value) {
                          if (widget.pollPostId == null) {
                            setState(() {
                              _visibility = value;
                              if (_restrictedAudience) _invitePreview = false;
                            });
                          }
                        },
                      ),
                      if (_visibility == 'Specific people')
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: TextFormField(
                            key: const Key('event-audience-usernames'),
                            controller: _audienceUsernames,
                            enabled: !_submitting,
                            autocorrect: false,
                            enableSuggestions: false,
                            textCapitalization: TextCapitalization.none,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 1700,
                            decoration: const InputDecoration(
                              labelText: 'Usernames',
                              hintText: '@alex, @sam',
                              helperText: 'Separate up to 50 usernames with commas or spaces.',
                              helperMaxLines: 2,
                            ),
                            validator: (_) {
                              final names = _selectedUsernames;
                              if (names.isEmpty) return 'Enter at least one username.';
                              if (names.length > 50) return 'Choose up to 50 people.';
                              if (names.any((name) => !RegExp(r'^[a-z0-9_]{3,30}$').hasMatch(name))) {
                                return 'Use 3–30 letters, numbers or underscores per username.';
                              }
                              return null;
                            },
                          ),
                        ),
                      const Divider(indent: 16),
                      SwitchListTile.adaptive(
                        key: const Key('event-invite-preview'),
                        value: _invitePreview,
                        onChanged: _submitting || _restrictedAudience
                            ? null
                            : (value) => setState(() => _invitePreview = value),
                        title: const Text('Show a preview on the invite link'),
                        subtitle: Text(
                          _restrictedAudience
                              ? 'Previews are off for a restricted audience. A link does not grant access.'
                              : 'Anyone with the link can see the title, date and description. Meeting details stay in the app.',
                        ),
                      ),
                      if (_invitePreview)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: TextFormField(
                            controller: _previewArea,
                            maxLength: 120,
                            validator: (value) =>
                                (value?.trim().length ?? 0) > 120
                                ? 'Use 120 characters or fewer.'
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Area shown on the invite',
                              hintText: 'e.g. Mannheim city centre',
                              helperText:
                                  'Optional. Use a neighbourhood or city.',
                            ),
                          ),
                        ),
                      if (widget.initialEvent == null &&
                          widget.pollPostId == null) ...[
                        const Divider(indent: 52),
                        AppChoiceField(
                          key: const Key('event-repeat-field'),
                          value: _repeat,
                          options: const [
                            'Does not repeat',
                            'Weekly · 4 events',
                            'Monthly · 3 events',
                          ],
                          label: 'Repeat',
                          enabled: !_submitting,
                          onChanged: (value) => setState(() => _repeat = value),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  key: const Key('publish-event-button'),
                  onPressed: _submitting || _preparingPhoto
                      ? null
                      : () => _submit(publish: true),
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
                        : (widget.initialEvent?.eventStatus == 'draft'
                              ? 'Publish event'
                              : widget.initialEvent == null
                              ? (_repeat == 'Does not repeat'
                                    ? 'Publish event'
                                    : 'Publish event series')
                              : 'Save changes'),
                  ),
                ),
                if (widget.pollPostId == null &&
                    (widget.initialEvent == null ||
                        widget.initialEvent?.eventStatus == 'draft')) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('save-event-draft-button'),
                    onPressed: _submitting || _preparingPhoto
                        ? null
                        : () => _submit(publish: false),
                    icon: const Icon(CupertinoIcons.doc),
                    label: const Text('Save draft'),
                  ),
                ],
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
      ),
    );
  }
}

String _summary(List<String> details, String fallback) =>
    details.isEmpty ? fallback : details.join(' · ');

class _OptionalEventSection extends StatelessWidget {
  const _OptionalEventSection({
    required this.sectionKey,
    required this.title,
    required this.summary,
    required this.icon,
    required this.controller,
    required this.enabled,
    required this.onExpansionChanged,
    required this.child,
    this.footer,
  });
  final String sectionKey;
  final String title;
  final String summary;
  final IconData icon;
  final ExpansibleController controller;
  final bool enabled;
  final ValueChanged<bool> onExpansionChanged;
  final Widget child;
  final String? footer;

  @override
  Widget build(BuildContext context) => AppSurface(
    borderRadius: 16,
    child: ExpansionTile(
      key: ValueKey(sectionKey),
      controller: controller,
      enabled: enabled,
      maintainState: true,
      onExpansionChanged: onExpansionChanged,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(
        icon,
        size: 21,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(
        summary,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      shape: const Border(),
      collapsedShape: const Border(),
      expansionAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 180),
      ),
      children: [
        const Divider(height: 1),
        child,
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              footer!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    ),
  );
}

class _EventIdeaDialog extends StatefulWidget {
  const _EventIdeaDialog();

  @override
  State<_EventIdeaDialog> createState() => _EventIdeaDialogState();
}

class _EventIdeaDialogState extends State<_EventIdeaDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Start with an idea'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tell us what you want to organize. We’ll fill in editable basics, but leave the place and time to you.',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('event-ai-idea-field'),
          controller: _controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'A relaxed photo walk for beginners…',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('event-ai-generate-button'),
        onPressed: () {
          final prompt = _controller.text.trim();
          Navigator.pop(context, prompt.length >= 10 ? prompt : null);
        },
        child: const Text('Fill the basics'),
      ),
    ],
  );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailingText,
    super.key,
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
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(title, style: const TextStyle(fontSize: 16)),
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
        ],
      ),
    ),
  );
}
