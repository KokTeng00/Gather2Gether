import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/location/location_service.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/member_controls.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.profile,
    required this.repository,
    required this.onCompleted,
    this.locationService = const LocationService(),
    super.key,
  });

  final UserProfile profile;
  final ProfileRepository repository;
  final LocationService locationService;
  final ValueChanged<UserProfile> onCompleted;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final Set<String> _selectedInterests = {...widget.profile.interests};
  late final Set<String> _selectedAccessibility = {
    ...widget.profile.accessibilityPreferences,
  };
  late double _radius = widget.profile.preferredRadiusKm;
  late double? _latitude = widget.profile.approximateLatitude;
  late double? _longitude = widget.profile.approximateLongitude;
  bool _saving = false;
  bool _findingLocation = false;

  Future<void> _useLocation() async {
    setState(() => _findingLocation = true);
    try {
      final position = await widget.locationService.currentPosition();
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is LocationFailure
                  ? error.message
                  : 'Could not get your approximate location.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _findingLocation = false);
    }
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      await widget.repository.completeOnboarding(
        interests: _selectedInterests.toList(growable: false),
        accessibilityPreferences: _selectedAccessibility.toList(
          growable: false,
        ),
        radiusKm: _radius,
        latitude: _latitude,
        longitude: _longitude,
      );
      if (!mounted) return;
      widget.onCompleted(
        widget.profile.copyWith(
          interests: _selectedInterests.toList(growable: false),
          accessibilityPreferences: _selectedAccessibility.toList(
            growable: false,
          ),
          preferredRadiusKm: _radius,
          approximateLatitude: _latitude,
          approximateLongitude: _longitude,
          onboardingCompletedAt: DateTime.now(),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save your setup. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                      colors.primaryContainer.withValues(alpha: 0.22),
                      theme.scaffoldBackgroundColor,
                    ),
                    theme.scaffoldBackgroundColor,
                    theme.scaffoldBackgroundColor,
                  ],
                  stops: const [0, 0.32, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: ListView(
              key: const Key('onboarding-content'),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              children: [
                const _OnboardingHeader(),
                const SizedBox(height: 34),
                _SectionHeading(
                  title: 'I’m up for…',
                  detail: _selectedInterests.isEmpty
                      ? 'Choose any that sound good'
                      : '${_selectedInterests.length} selected',
                ),
                const SizedBox(height: 14),
                _InterestGrid(
                  selected: _selectedInterests,
                  onChanged: (interest, selected) => setState(
                    () => selected
                        ? _selectedInterests.add(interest)
                        : _selectedInterests.remove(interest),
                  ),
                ),
                const SizedBox(height: 34),
                const _SectionHeading(
                  title: 'Make plans easier',
                  detail: 'We’ll prioritise events with these details',
                ),
                const SizedBox(height: 14),
                _PreferencePanel(
                  selected: _selectedAccessibility,
                  onChanged: (preference, selected) => setState(
                    () => selected
                        ? _selectedAccessibility.add(preference)
                        : _selectedAccessibility.remove(preference),
                  ),
                ),
                const SizedBox(height: 34),
                _DistancePanel(
                  radius: _radius,
                  hasLocation: _latitude != null && _longitude != null,
                  findingLocation: _findingLocation,
                  onRadiusChanged: (value) => setState(() => _radius = value),
                  onUseLocation: _useLocation,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _SubmitBar(saving: _saving, onPressed: _finish),
    );
  }
}

class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const AppBrandMark(size: 42),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                'Gather2Gether',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'QUICK SETUP',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontSize: 11,
                letterSpacing: 0.7,
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        Text(
          'What gets you out\nof the house?',
          key: const Key('onboarding-headline'),
          style: theme.textTheme.displaySmall?.copyWith(
            color: colors.onSurface,
            fontSize: 38,
            height: 1.02,
            letterSpacing: -1.3,
          ),
        ),
        const SizedBox(height: 13),
        Text(
          'Pick a few things you’d actually enjoy. We’ll use them to make Discover feel more like your neighbourhood.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          detail,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _InterestGrid extends StatelessWidget {
  const _InterestGrid({required this.selected, required this.onChanged});

  final Set<String> selected;
  final void Function(String interest, bool selected) onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columnCount = constraints.maxWidth >= 520 ? 3 : 2;
      const spacing = 10.0;
      final tileWidth =
          (constraints.maxWidth - spacing * (columnCount - 1)) / columnCount;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: memberInterestOptions
            .map(
              (interest) => SizedBox(
                width: tileWidth,
                child: _InterestTile(
                  interest: interest,
                  selected: selected.contains(interest),
                  onChanged: (value) => onChanged(interest, value),
                ),
              ),
            )
            .toList(growable: false),
      );
    },
  );
}

class _InterestTile extends StatelessWidget {
  const _InterestTile({
    required this.interest,
    required this.selected,
    required this.onChanged,
  });

  final String interest;
  final bool selected;
  final ValueChanged<bool> onChanged;

  String get _visualName => switch (interest) {
    'Sports' => 'Badminton',
    'Outdoors' => 'Hiking',
    'Games' => 'Board games',
    'Languages' => 'Language exchange',
    'Technology' => 'Startup',
    'Arts' => 'Event ideas',
    'Wellness' => 'Running',
    'Volunteering' => 'Looking for group',
    _ => interest,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visual = CategoryVisual.resolve(context, _visualName);
    final borderColor = selected
        ? visual.ink.withValues(alpha: 0.5)
        : colors.outlineVariant.withValues(alpha: 0.82);
    return Semantics(
      button: true,
      selected: selected,
      label: interest,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? visual.background : colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('onboarding-interest-$interest'),
            onTap: () => onChanged(!selected),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 58),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Icon(visual.icon, color: visual.ink, size: 20),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        interest,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: selected ? visual.ink : colors.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 4),
                      Icon(
                        CupertinoIcons.checkmark_circle_fill,
                        color: visual.ink,
                        size: 18,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreferencePanel extends StatelessWidget {
  const _PreferencePanel({required this.selected, required this.onChanged});

  final Set<String> selected;
  final void Function(String preference, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.82),
        ),
      ),
      child: Column(
        children: [
          _PreferenceRow(
            preference: 'wheelchair_accessible',
            title: 'Wheelchair access',
            subtitle: 'Prioritise venues marked step-free',
            icon: CupertinoIcons.person_crop_circle_badge_checkmark,
            selected: selected.contains('wheelchair_accessible'),
            onChanged: onChanged,
          ),
          Divider(
            height: 1,
            indent: 62,
            color: colors.outlineVariant.withValues(alpha: 0.65),
          ),
          _PreferenceRow(
            preference: 'beginner_friendly',
            title: 'Newcomer friendly',
            subtitle: 'Prefer events that welcome first-timers',
            icon: Icons.waving_hand_rounded,
            selected: selected.contains('beginner_friendly'),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.preference,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onChanged,
  });

  final String preference;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final void Function(String preference, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('onboarding-preference-$preference'),
        onTap: () => onChanged(preference, !selected),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: colors.onPrimaryContainer, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: selected,
                onChanged: (value) => onChanged(preference, value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DistancePanel extends StatelessWidget {
  const _DistancePanel({
    required this.radius,
    required this.hasLocation,
    required this.findingLocation,
    required this.onRadiusChanged,
    required this.onUseLocation,
  });

  final double radius;
  final bool hasLocation;
  final bool findingLocation;
  final ValueChanged<double> onRadiusChanged;
  final VoidCallback onUseLocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.82),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 17, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How far would you go?',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Set the starting range for Discover',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  key: const Key('onboarding-radius-value'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${radius.round()} km',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Slider(
            key: const Key('onboarding-radius-slider'),
            value: radius.clamp(1, 100),
            min: 1,
            max: 100,
            divisions: 99,
            semanticFormatterCallback: (value) => '${value.round()} kilometres',
            onChanged: onRadiusChanged,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '1 km',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '100 km',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: colors.outlineVariant.withValues(alpha: 0.65),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('onboarding-location-button'),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(20),
              ),
              onTap: findingLocation ? null : onUseLocation,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 15),
                child: Row(
                  children: [
                    if (findingLocation)
                      const SizedBox.square(
                        dimension: 36,
                        child: Center(child: CupertinoActivityIndicator()),
                      )
                    else
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: hasLocation
                              ? colors.primaryContainer
                              : colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          hasLocation
                              ? CupertinoIcons.checkmark_alt
                              : CupertinoIcons.location_fill,
                          color: hasLocation
                              ? colors.onPrimaryContainer
                              : colors.primary,
                          size: 19,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            findingLocation
                                ? 'Finding your area…'
                                : hasLocation
                                ? 'Current area saved'
                                : 'Use my current area',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            hasLocation
                                ? 'Tap to refresh your approximate location'
                                : 'Approximate only — never your exact address',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      color: colors.onSurfaceVariant,
                      size: 17,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.saving, required this.onPressed});

  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              key: const Key('complete-onboarding'),
              onPressed: saving ? null : onPressed,
              child: saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continue'),
            ),
            const SizedBox(height: 7),
            Text(
              'Change any of this later in Settings',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
