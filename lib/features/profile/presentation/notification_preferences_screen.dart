import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_settings.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/member_controls.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({required this.repository, super.key});

  final ProfileRepository repository;

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  NotificationPreferences? _preferences;
  NotificationPreferences? _savedPreferences;
  Object? _error;
  bool _saving = false;

  bool get _hasChanges {
    final current = _preferences;
    final saved = _savedPreferences;
    if (current == null || saved == null) return false;
    return current.pushEnabled != saved.pushEnabled ||
        current.remindersEnabled != saved.remindersEnabled ||
        current.announcementsEnabled != saved.announcementsEnabled ||
        current.discussionEnabled != saved.discussionEnabled ||
        current.recommendationsEnabled != saved.recommendationsEnabled ||
        current.quietStartMinute != saved.quietStartMinute ||
        current.quietEndMinute != saved.quietEndMinute;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    try {
      final preferences = await widget.repository.notificationPreferences();
      if (mounted) {
        setState(() {
          _preferences = preferences;
          _savedPreferences = preferences;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _save() async {
    final preferences = _preferences;
    if (preferences == null || _saving || !_hasChanges) return;
    setState(() => _saving = true);
    try {
      await widget.repository.updateNotificationPreferences(preferences);
      if (mounted) {
        setState(() => _savedPreferences = preferences);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification preferences saved.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save notification preferences.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickQuietTime({required bool start}) async {
    final preferences = _preferences!;
    final current = start
        ? preferences.quietStartMinute ?? 22 * 60
        : preferences.quietEndMinute ?? 7 * 60;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (selected == null || !mounted) return;
    final minute = selected.hour * 60 + selected.minute;
    setState(
      () => _preferences = start
          ? preferences.copyWith(quietStartMinute: minute)
          : preferences.copyWith(quietEndMinute: minute),
    );
  }

  String _time(int minute) =>
      TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          AppSaveAction(
            buttonKey: const Key('save-notification-preferences-button'),
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
                const AppSettingsHeading('Delivery'),
                AppSettingsGroup(
                  dividerIndent: 16,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 3,
                      ),
                      title: const Text('Push notifications'),
                      value: preferences.pushEnabled,
                      onChanged: _saving
                          ? null
                          : (value) => setState(
                              () => _preferences = preferences.copyWith(
                                pushEnabled: value,
                              ),
                            ),
                    ),
                  ],
                ),
                const AppSettingsCaption(
                  'Control push notifications on this account.',
                ),
                const SizedBox(height: 24),
                const AppSettingsHeading('Event alerts'),
                AppSettingsGroup(
                  dividerIndent: 16,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 3,
                      ),
                      title: const Text('Event reminders'),
                      value: preferences.remindersEnabled,
                      onChanged: _saving
                          ? null
                          : (value) => setState(
                              () => _preferences = preferences.copyWith(
                                remindersEnabled: value,
                              ),
                            ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 3,
                      ),
                      title: const Text('Host announcements'),
                      value: preferences.announcementsEnabled,
                      onChanged: _saving
                          ? null
                          : (value) => setState(
                              () => _preferences = preferences.copyWith(
                                announcementsEnabled: value,
                              ),
                            ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 3,
                      ),
                      title: const Text('Discussion replies'),
                      value: preferences.discussionEnabled,
                      onChanged: _saving
                          ? null
                          : (value) => setState(
                              () => _preferences = preferences.copyWith(
                                discussionEnabled: value,
                              ),
                            ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 3,
                      ),
                      title: const Text('Discovery alerts'),
                      value: preferences.recommendationsEnabled,
                      onChanged: _saving
                          ? null
                          : (value) => setState(
                              () => _preferences = preferences.copyWith(
                                recommendationsEnabled: value,
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const AppSettingsHeading('Quiet hours'),
                AppSettingsGroup(
                  dividerIndent: 16,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 3,
                      ),
                      title: const Text('Quiet hours'),
                      value: preferences.quietStartMinute != null,
                      onChanged: _saving
                          ? null
                          : (value) => setState(
                              () => _preferences = value
                                  ? preferences.copyWith(
                                      quietStartMinute: 22 * 60,
                                      quietEndMinute: 7 * 60,
                                    )
                                  : preferences.copyWith(clearQuietHours: true),
                            ),
                    ),
                    if (preferences.quietStartMinute != null) ...[
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 3,
                        ),
                        title: const Text('Starts'),
                        trailing: Text(_time(preferences.quietStartMinute!)),
                        onTap: () => _pickQuietTime(start: true),
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 3,
                        ),
                        title: const Text('Ends'),
                        trailing: Text(_time(preferences.quietEndMinute!)),
                        onTap: () => _pickQuietTime(start: false),
                      ),
                    ],
                  ],
                ),
                const AppSettingsCaption(
                  'Event cancellations and waitlist promotions can still arrive during quiet hours.',
                ),
              ],
            ),
    );
  }
}
