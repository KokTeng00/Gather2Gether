import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_settings.dart';
import 'package:gather2gether/core/theme/app_settings_picker.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/member_controls.dart';

class RecommendationSettingsScreen extends StatefulWidget {
  const RecommendationSettingsScreen({required this.repository, super.key});

  final ProfileRepository repository;

  @override
  State<RecommendationSettingsScreen> createState() =>
      _RecommendationSettingsScreenState();
}

class _RecommendationSettingsScreenState
    extends State<RecommendationSettingsScreen> {
  static const _categories = [
    'Badminton',
    'Running',
    'Padel',
    'Hiking',
    'Coffee',
    'Board Games',
    'Language Exchange',
    'Photography',
    'Startup',
    'Cycling',
    'Other',
    'General',
    'Looking for group',
    'Local tips',
    'Event ideas',
    'Safety',
  ];
  RecommendationPreferences? _preferences;
  final Set<String> _hidden = {};
  final Set<String> _savedHidden = {};
  bool _savedEnabled = true;
  bool _saving = false;
  Object? _error;

  bool get _hasChanges {
    final preferences = _preferences;
    if (preferences == null) return false;
    return preferences.enabled != _savedEnabled ||
        _hidden.length != _savedHidden.length ||
        !_hidden.containsAll(_savedHidden);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final preferences = await widget.repository.recommendationPreferences();
      if (!mounted) return;
      setState(() {
        _preferences = preferences;
        _hidden
          ..clear()
          ..addAll(preferences.hiddenCategories);
        _savedHidden
          ..clear()
          ..addAll(preferences.hiddenCategories);
        _savedEnabled = preferences.enabled;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _save() async {
    final preferences = _preferences;
    if (preferences == null || _saving || !_hasChanges) return;
    setState(() => _saving = true);
    try {
      await widget.repository.updateRecommendationPreferences(
        enabled: preferences.enabled,
        hiddenCategories: _hidden.toList(growable: false),
      );
      if (!mounted) return;
      setState(() {
        _savedEnabled = preferences.enabled;
        _savedHidden
          ..clear()
          ..addAll(_hidden);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Recommendations saved.')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save recommendation settings.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseCategories() async {
    final selected = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => AppSettingsPicker(
          title: 'Hidden categories',
          description:
              'Selected categories will not appear in recommendations.',
          searchHint: 'Search categories',
          selected: _hidden,
          groups: [
            AppSettingsOptionGroup({
              for (final category in _categories.take(11)) category: category,
            }, title: 'Events'),
            AppSettingsOptionGroup({
              for (final category in _categories.skip(11)) category: category,
            }, title: 'Community'),
          ],
        ),
      ),
    );
    if (mounted && selected != null) {
      setState(
        () => _hidden
          ..clear()
          ..addAll(selected),
      );
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset recommendations?'),
        content: const Text(
          'This clears the activity used for recommendations, restores hidden content and turns personalization on.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) await _reset();
  }

  Future<void> _reset() async {
    setState(() => _saving = true);
    try {
      await widget.repository.resetRecommendationControls();
      if (!mounted) return;
      setState(() {
        _hidden.clear();
        _savedHidden.clear();
        _savedEnabled = true;
        _preferences = const RecommendationPreferences(
          enabled: true,
          hiddenCategories: [],
          hiddenCount: 0,
        );
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not reset recommendations.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recommendations'),
        actions: [
          AppSaveAction(
            buttonKey: const Key('save-recommendation-preferences-button'),
            saving: _saving,
            onPressed: _hasChanges ? _save : null,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: preferences == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : FilledButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
            )
          : SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                    children: [
                      const AppSettingsHeading('Your feed'),
                      AppSettingsGroup(
                        dividerIndent: 16,
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 3,
                            ),
                            title: const Text('Personalize my feed'),
                            value: preferences.enabled,
                            onChanged: _saving
                                ? null
                                : (value) => setState(
                                    () => _preferences =
                                        RecommendationPreferences(
                                          enabled: value,
                                          hiddenCategories: _hidden.toList(
                                            growable: false,
                                          ),
                                          hiddenCount: preferences.hiddenCount,
                                        ),
                                  ),
                          ),
                        ],
                      ),
                      const AppSettingsCaption(
                        'Use your activity to order recommendations. When off, nearby events appear in date order.',
                      ),
                      const SizedBox(height: 24),
                      const AppSettingsHeading('Content preferences'),
                      AppSettingsGroup(
                        children: [
                          AppSettingsRow(
                            key: const Key('recommendation-hidden-categories'),
                            icon: CupertinoIcons.eye_slash,
                            title: 'Hidden categories',
                            subtitle: _hidden.isEmpty
                                ? 'All categories are shown'
                                : '${_hidden.take(2).join(', ')}'
                                      '${_hidden.length > 2 ? ' + ${_hidden.length - 2} more' : ''}',
                            onTap: _saving ? null : _chooseCategories,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      AppSettingsGroup(
                        children: [
                          AppSettingsRow(
                            key: const Key('reset-recommendations-button'),
                            icon: CupertinoIcons.arrow_counterclockwise,
                            title: 'Reset recommendations',
                            onTap: _saving ? null : _confirmReset,
                          ),
                        ],
                      ),
                      const AppSettingsCaption(
                        'Start fresh with your recommendations and show hidden content again.',
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
