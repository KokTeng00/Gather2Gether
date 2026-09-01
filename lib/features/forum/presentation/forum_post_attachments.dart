import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';
import 'package:url_launcher/url_launcher.dart';

typedef ForumUrlLauncher = Future<bool> Function(Uri uri);

class ForumPostImage extends StatelessWidget {
  const ForumPostImage({
    required this.postId,
    required this.title,
    required this.repository,
    this.aspectRatio = 4 / 3,
    this.borderRadius = 18,
    super.key,
  });

  final String postId;
  final String title;
  final ForumRepository repository;
  final double aspectRatio;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      label: 'Photo attached to $title',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cacheWidth =
                    (constraints.maxWidth *
                            MediaQuery.devicePixelRatioOf(context))
                        .round()
                        .clamp(320, 2400);
                return Image.network(
                  repository.mediaUrl(postId),
                  headers: repository.mediaHeaders(),
                  fit: BoxFit.cover,
                  cacheWidth: cacheWidth,
                  gaplessPlayback: true,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : ColoredBox(
                          color: colors.surfaceContainerHighest,
                          child: const Center(
                            child: CupertinoActivityIndicator(),
                          ),
                        ),
                  errorBuilder: (_, _, _) => _ImageFallback(colors: colors),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: colors.surfaceContainerHighest,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.photo, color: colors.onSurfaceVariant, size: 28),
          const SizedBox(height: 7),
          Text(
            'Photo unavailable',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class ForumPlaceCard extends StatelessWidget {
  const ForumPlaceCard({
    required this.name,
    required this.address,
    this.compact = false,
    this.launcher,
    super.key,
  });

  final String name;
  final String address;
  final bool compact;
  final ForumUrlLauncher? launcher;

  Uri get mapsUri => Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': '$name, $address',
  });

  Future<void> _open(BuildContext context) async {
    var opened = false;
    try {
      opened = await (launcher ?? _launch)(mapsUri);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this place in Maps.')),
      );
    }
  }

  static Future<bool> _launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Open $name, $address in Maps',
      child: Material(
        color: colors.primaryContainer.withValues(alpha: compact ? 0.42 : 0.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 13 : 16),
          side: BorderSide(color: colors.primary.withValues(alpha: 0.14)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(context),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 13,
              vertical: compact ? 8 : 12,
            ),
            child: Row(
              children: [
                Container(
                  width: compact ? 28 : 38,
                  height: compact ? 28 : 38,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(compact ? 9 : 12),
                  ),
                  child: Icon(
                    CupertinoIcons.location_fill,
                    size: compact ? 15 : 19,
                    color: colors.onPrimary,
                  ),
                ),
                SizedBox(width: compact ? 9 : 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        address,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  CupertinoIcons.arrow_up_right,
                  size: compact ? 14 : 16,
                  color: colors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
