import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/features/places/data/place_repository.dart';
import 'package:gather2gether/features/places/domain/place_suggestion.dart';

class PlaceAutocompleteField extends StatefulWidget {
  const PlaceAutocompleteField({
    required this.controller,
    required this.repository,
    required this.onSelected,
    required this.onTextChanged,
    required this.validator,
    this.latitude,
    this.longitude,
    this.enabled = true,
    this.fieldKey = const Key('event-address-field'),
    this.decoration,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final PlaceRepository repository;
  final ValueChanged<PlaceSuggestion> onSelected;
  final VoidCallback onTextChanged;
  final FormFieldValidator<String> validator;
  final double? latitude;
  final double? longitude;
  final bool enabled;
  final Key fieldKey;
  final InputDecoration? decoration;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PlaceAutocompleteField> createState() => _PlaceAutocompleteFieldState();
}

class _PlaceAutocompleteFieldState extends State<PlaceAutocompleteField> {
  static const _debounceDuration = Duration(milliseconds: 450);

  final _focusNode = FocusNode();
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = const [];
  String? _error;
  bool _loading = false;
  int _requestGeneration = 0;

  @override
  void dispose() {
    _requestGeneration += 1;
    _debounce?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    widget.onTextChanged();
    _debounce?.cancel();
    final generation = ++_requestGeneration;
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _suggestions = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _suggestions = const [];
      _error = null;
      _loading = false;
    });
    _debounce = Timer(_debounceDuration, () => _search(query, generation));
  }

  Future<void> _search(String query, int generation) async {
    if (!mounted || generation != _requestGeneration) return;
    setState(() => _loading = true);
    try {
      final results = await widget.repository.autocomplete(
        text: query,
        latitude: widget.latitude,
        longitude: widget.longitude,
        language: Localizations.localeOf(context).languageCode,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _suggestions = results;
        _error = results.isEmpty ? 'No matching address found.' : null;
      });
    } on PlaceSearchException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _suggestions = const [];
        _error = switch (error.code) {
          'route_not_found' || 'places_not_configured' =>
            'Address search is being set up. Please try again shortly.',
          _ => error.message,
        };
      });
    } on TimeoutException {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _suggestions = const [];
        _error = 'Address suggestions took too long. Please retry.';
      });
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _suggestions = const [];
        _error = 'Address suggestions are temporarily unavailable.';
      });
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  void _select(PlaceSuggestion place) {
    _debounce?.cancel();
    _requestGeneration += 1;
    widget.controller.text = place.formattedAddress;
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    setState(() {
      _suggestions = const [];
      _error = null;
      _loading = false;
    });
    _focusNode.unfocus();
    widget.onSelected(place);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: widget.fieldKey,
          controller: widget.controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          keyboardType: TextInputType.streetAddress,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.fullStreetAddress],
          decoration:
              (widget.decoration ??
                      const InputDecoration(
                        hintText: 'Search for a venue or address',
                        prefixIcon: Icon(CupertinoIcons.map_pin_ellipse),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                      ))
                  .copyWith(
                    suffixIcon: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: CupertinoActivityIndicator(),
                          )
                        : null,
                  ),
          validator: widget.validator,
          onChanged: _onChanged,
          onFieldSubmitted: widget.onSubmitted,
        ),
        if (_suggestions.isNotEmpty)
          Material(
            color: colors.surfaceContainerLow,
            shape: Border(top: BorderSide(color: colors.outlineVariant)),
            child: Column(
              children: [
                for (final place in _suggestions)
                  ListTile(
                    key: ValueKey('place-suggestion-${place.id}'),
                    dense: true,
                    leading: const Icon(CupertinoIcons.location_fill, size: 20),
                    title: Text(
                      place.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: place.displaySubtitle == null
                        ? null
                        : Text(
                            place.displaySubtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onTap: () => _select(place),
                  ),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              _error!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ),
      ],
    );
  }
}
