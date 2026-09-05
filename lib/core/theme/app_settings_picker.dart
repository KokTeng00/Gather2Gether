import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_settings.dart';

class AppSettingsOptionGroup {
  const AppSettingsOptionGroup(this.options, {this.title});
  final Map<String, String> options;
  final String? title;
}

/// Edits a local selection; the parent settings screen owns persistence.
class AppSettingsPicker extends StatefulWidget {
  const AppSettingsPicker({
    required this.title,
    required this.groups,
    required this.selected,
    this.description,
    this.searchHint,
    this.multiple = true,
    super.key,
  });

  final String title;
  final List<AppSettingsOptionGroup> groups;
  final Set<String> selected;
  final String? description;
  final String? searchHint;
  final bool multiple;

  @override
  State<AppSettingsPicker> createState() => _AppSettingsPickerState();
}

class _AppSettingsPickerState extends State<AppSettingsPicker> {
  late final _selected = {...widget.selected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups
        .map(
          (group) => AppSettingsOptionGroup(
            Map.fromEntries(
              group.options.entries.where(
                (entry) => entry.value.toLowerCase().contains(_query),
              ),
            ),
            title: group.title,
          ),
        )
        .where((group) => group.options.isNotEmpty)
        .toList();
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.multiple)
            TextButton(
              key: const Key('settings-picker-done'),
              onPressed: () => Navigator.of(context).pop(_selected),
              child: const Text('Done'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
              children: [
                if (widget.searchHint != null) ...[
                  TextField(
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: widget.searchHint,
                      prefixIcon: const Icon(CupertinoIcons.search, size: 20),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                if (widget.description != null) ...[
                  Text(
                    widget.description!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                for (final group in groups) ...[
                  if (group.title != null) AppSettingsHeading(group.title!),
                  AppSettingsGroup(
                    dividerIndent: 16,
                    children: [
                      for (final entry in group.options.entries)
                        Semantics(
                          enabled: true,
                          checked: widget.multiple
                              ? _selected.contains(entry.key)
                              : null,
                          selected: widget.multiple
                              ? null
                              : _selected.contains(entry.key),
                          inMutuallyExclusiveGroup: !widget.multiple,
                          child: AppSettingsRow(
                            key: ValueKey('settings-option-${entry.key}'),
                            title: entry.value,
                            trailing: Icon(
                              _selected.contains(entry.key)
                                  ? CupertinoIcons.checkmark
                                  : widget.multiple
                                  ? CupertinoIcons.circle
                                  : null,
                              size: 20,
                              color: _selected.contains(entry.key)
                                  ? colors.primary
                                  : colors.onSurfaceVariant.withValues(
                                      alpha: 0.65,
                                    ),
                            ),
                            onTap: () {
                              if (!widget.multiple) {
                                Navigator.of(context).pop(<String>{entry.key});
                                return;
                              }
                              setState(() {
                                if (!_selected.remove(entry.key)) {
                                  _selected.add(entry.key);
                                }
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
                if (groups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No matches found.',
                      textAlign: TextAlign.center,
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
