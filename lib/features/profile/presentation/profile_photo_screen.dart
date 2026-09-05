import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ProfilePhotoScreen extends StatelessWidget {
  const ProfilePhotoScreen({
    required this.imageUrl,
    required this.name,
    this.headers,
    super.key,
  });
  final String imageUrl;
  final String name;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Profile photo'),
      leading: IconButton(
        tooltip: 'Close photo',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(CupertinoIcons.xmark),
      ),
    ),
    body: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.network(
                  imageUrl,
                  headers: headers,
                  fit: BoxFit.contain,
                  semanticLabel: name.isEmpty
                      ? 'Profile photo'
                      : '$name profile photo',
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const SizedBox(
                          height: 240,
                          child: Center(
                            child: CircularProgressIndicator.adaptive(),
                          ),
                        ),
                  errorBuilder: (context, error, stack) => Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.photo,
                          size: 36,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Photo could not be loaded.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
