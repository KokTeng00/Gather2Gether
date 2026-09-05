import 'package:flutter/material.dart';
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
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Personalized ordering'),
                  subtitle: const Text(
                    'Uses your in-app event and community activity. Turning this off keeps nearby chronological results.',
                  ),
                  value: preferences.enabled,
                  onChanged: _saving
                      ? null
                      : (value) => setState(
                          () => _preferences = RecommendationPreferences(
                            enabled: value,
                            hiddenCategories: _hidden.toList(growable: false),
                            hiddenCount: preferences.hiddenCount,
                          ),
                        ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Hide categories',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _categories
                      .map(
                        (category) => FilterChip(
                          label: Text(category),
                          selected: _hidden.contains(category),
                          onSelected: _saving
                              ? null
                              : (selected) => setState(
                                  () => selected
                                      ? _hidden.add(category)
                                      : _hidden.remove(category),
                                ),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 18),
                OutlinedButton(
                  key: const Key('reset-recommendations-button'),
                  onPressed: _saving ? null : _reset,
                  child: const Text('Reset recommendations'),
                ),
              ],
            ),
    );
  }
}
