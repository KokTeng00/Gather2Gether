import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_settings.dart';
import 'package:gather2gether/core/theme/appearance_controller.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({this.controller, super.key});
  final AppearanceController? controller;
  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  late final _controller = widget.controller ?? AppearanceController.instance;
  bool _saving = false;
  Future<void> _select(ThemeMode mode) async {
    setState(() => _saving = true);
    try {
      await _controller.setMode(mode);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save appearance. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Appearance')),
    body: SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppSettingsHeading('Color theme'),
                    AppSettingsGroup(
                      children: [
                        for (final mode in ThemeMode.values)
                          Semantics(
                            selected: _controller.mode == mode,
                            inMutuallyExclusiveGroup: true,
                            child: AppSettingsRow(
                              key: Key('appearance-${mode.name}'),
                              title: switch (mode) {
                                ThemeMode.system => 'System',
                                ThemeMode.light => 'Light',
                                ThemeMode.dark => 'Dark',
                              },
                              icon: switch (mode) {
                                ThemeMode.system =>
                                  CupertinoIcons.device_phone_portrait,
                                ThemeMode.light => CupertinoIcons.sun_max,
                                ThemeMode.dark => CupertinoIcons.moon,
                              },
                              trailing: _controller.mode == mode
                                  ? Icon(
                                      CupertinoIcons.checkmark,
                                      size: 20,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    )
                                  : const SizedBox(width: 20),
                              onTap: _saving ? null : () => _select(mode),
                            ),
                          ),
                      ],
                    ),
                    const AppSettingsCaption(
                      'System follows your device appearance. Your choice applies throughout the app and is saved on this device.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
