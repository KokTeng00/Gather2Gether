import 'package:flutter/material.dart';
import 'package:gather2gether/config/app_config.dart';
import 'package:url_launcher/url_launcher.dart';

/// Available before sign-in as well as in Settings > About.
class SupportLinks extends StatelessWidget {
  const SupportLinks({super.key});

  Future<void> _open(BuildContext context, Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Keep the destination visible when the device cannot open a browser.
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open this link'),
        content: SelectableText(uri.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    children: [
      for (final entry in const {
        'Privacy': 'privacy',
        'Community rules': 'terms',
        'Delete account': 'account-deletion',
        'Help & feedback': 'support',
      }.entries)
        TextButton(
          onPressed: () => _open(context, AppConfig.publicPage(entry.value)),
          child: Text(entry.key),
        ),
    ],
  );
}
