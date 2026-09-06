import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_sheet.dart';
import 'package:gather2gether/core/constants/forum_constants.dart';
import 'package:gather2gether/core/media/app_image_picker.dart';
import 'package:gather2gether/core/media/prepared_image.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';
import 'package:gather2gether/features/places/data/place_repository.dart';
import 'package:gather2gether/features/places/presentation/place_autocomplete_field.dart';

class CreateForumPostScreen extends StatefulWidget {
  const CreateForumPostScreen({
    super.key,
    this.asSheet = false,
    ForumRepository? repository,
    AppImagePicker? imagePicker,
    PlaceRepository? placeRepository,
  }) : _repository = repository,
       _imagePicker = imagePicker,
       _placeRepository = placeRepository;

  final bool asSheet;
  final ForumRepository? _repository;
  final AppImagePicker? _imagePicker;
  final PlaceRepository? _placeRepository;

  @override
  State<CreateForumPostScreen> createState() => _CreateForumPostScreenState();
}

class _CreateForumPostScreenState extends State<CreateForumPostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  late final ForumRepository _repository;
  late final AppImagePicker _imagePicker;
  late final PlaceRepository _places;
  String _category = forumCategories.first;
  PreparedImage? _image;
  String? _placeName;
  String? _placeAddress;
  bool _preparingImage = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _repository = widget._repository ?? ForumRepository();
    _imagePicker = widget._imagePicker ?? AppImagePicker();
    _places = widget._placeRepository ?? PlaceRepository();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_recoverLostImage());
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      final id = await _repository.createPost(
        title: _title.text,
        body: _body.text,
        category: _category,
        image: _image,
        placeName: _placeName,
        placeAddress: _placeAddress,
      );
      if (mounted) Navigator.of(context).pop(id);
    } on ForumApiException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) _showError('Could not publish the discussion. Try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _recoverLostImage() async {
    try {
      final recovered = await _imagePicker.recoverLostImage();
      if (recovered == null || !mounted || _image != null) return;
      setState(() => _image = recovered);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your selected photo was restored.')),
      );
    } on AppImagePickException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _choosePhoto() async {
    final source = await showCupertinoModalPopup<AppImageSource>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(_image == null ? 'Add a photo' : 'Change photo'),
        message: const Text(
          'Photos are resized and location metadata is removed before upload.',
        ),
        actions: [
          CupertinoActionSheetAction(
            key: const Key('forum-photo-gallery'),
            onPressed: () => Navigator.of(context).pop(AppImageSource.gallery),
            child: const Text('Choose from Library'),
          ),
          CupertinoActionSheetAction(
            key: const Key('forum-photo-camera'),
            onPressed: () => Navigator.of(context).pop(AppImageSource.camera),
            child: const Text('Take Photo'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (source == null || !mounted) return;

    setState(() => _preparingImage = true);
    try {
      final image = await _imagePicker.pickImage(source);
      if (image != null && mounted) setState(() => _image = image);
    } on AppImagePickException catch (error) {
      if (mounted) _showError(error.message);
    } catch (_) {
      if (mounted) _showError('Could not prepare that photo. Try again.');
    } finally {
      if (mounted) setState(() => _preparingImage = false);
    }
  }

  Future<void> _editPlace() async {
    final place = await showModalBottomSheet<_PlaceDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _PlaceEditorSheet(
        repository: _places,
        initialName: _placeName,
        initialAddress: _placeAddress,
      ),
    );
    if (place == null || !mounted) return;
    setState(() {
      _placeName = place.name;
      _placeAddress = place.address;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetScaffold(
      asSheet: widget.asSheet,
      canDismiss: !_submitting,
      title: 'New discussion',
      bodyBuilder: (context, scrollController) => SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            controller: scrollController,
            physics: const ClampingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              Text(
                'Ask a question or share an idea with people nearby.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              AppSection(
                title: 'Discussion',
                child: Column(
                  children: [
                    AppChoiceField(
                      key: const Key('forum-category-field'),
                      value: _category,
                      options: forumCategories,
                      label: 'Topic',
                      enabled: !_submitting,
                      onChanged: (value) => setState(() => _category = value),
                    ),
                    const Divider(indent: 52),
                    TextFormField(
                      controller: _title,
                      enabled: !_submitting,
                      maxLength: 120,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Give it a clear title',
                        prefixIcon: Icon(CupertinoIcons.textformat),
                        counterText: '',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 5
                          ? 'Use at least 5 characters.'
                          : null,
                    ),
                    const Divider(indent: 52),
                    TextFormField(
                      controller: _body,
                      enabled: !_submitting,
                      minLines: 7,
                      maxLines: 14,
                      maxLength: 4000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText:
                            'Add context so others can give a useful reply…',
                        counterText: '',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 10
                          ? 'Use at least 10 characters.'
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              AppSection(
                title: 'Add to your post',
                footer: 'Optional · Share one photo and tag one public place.',
                child: _AttachmentsPanel(
                  image: _image,
                  placeName: _placeName,
                  placeAddress: _placeAddress,
                  preparingImage: _preparingImage,
                  enabled: !_submitting,
                  onChoosePhoto: _choosePhoto,
                  onRemovePhoto: () => setState(() => _image = null),
                  onEditPlace: _editPlace,
                  onRemovePlace: () => setState(() {
                    _placeName = null;
                    _placeAddress = null;
                  }),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      CupertinoIcons.checkmark_shield_fill,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Only tag public venues. Keep home addresses, phone numbers, and other private information out of discussions.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              FilledButton.icon(
                key: const Key('publish-discussion-button'),
                onPressed: _submitting || _preparingImage ? null : _submit,
                icon: _submitting
                    ? CupertinoActivityIndicator(
                        color: Theme.of(context).colorScheme.onPrimary,
                      )
                    : const Icon(CupertinoIcons.paperplane_fill),
                label: Text(_submitting ? 'Publishing…' : 'Publish Discussion'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentsPanel extends StatelessWidget {
  const _AttachmentsPanel({
    required this.image,
    required this.placeName,
    required this.placeAddress,
    required this.preparingImage,
    required this.enabled,
    required this.onChoosePhoto,
    required this.onRemovePhoto,
    required this.onEditPlace,
    required this.onRemovePlace,
  });

  final PreparedImage? image;
  final String? placeName;
  final String? placeAddress;
  final bool preparingImage;
  final bool enabled;
  final VoidCallback onChoosePhoto;
  final VoidCallback onRemovePhoto;
  final VoidCallback onEditPlace;
  final VoidCallback onRemovePlace;

  @override
  Widget build(BuildContext context) {
    final hasPlace = placeName != null && placeAddress != null;
    return Column(
      children: [
        if (image == null)
          _AttachmentActionRow(
            key: const Key('forum-add-photo'),
            icon: CupertinoIcons.photo_on_rectangle,
            title: preparingImage ? 'Preparing photo…' : 'Add a photo',
            subtitle: 'Share one clear image from your day',
            onTap: enabled && !preparingImage ? onChoosePhoto : null,
            trailing: preparingImage
                ? const CupertinoActivityIndicator()
                : null,
          )
        else
          _PhotoPreview(
            image: image!,
            preparing: preparingImage,
            enabled: enabled,
            onChange: onChoosePhoto,
            onRemove: onRemovePhoto,
          ),
        const Divider(height: 1),
        if (!hasPlace)
          _AttachmentActionRow(
            key: const Key('forum-add-place'),
            icon: CupertinoIcons.location,
            title: 'Tag a public place',
            subtitle: 'Add a venue, park, café, or landmark',
            onTap: enabled ? onEditPlace : null,
          )
        else
          _SelectedPlace(
            name: placeName!,
            address: placeAddress!,
            enabled: enabled,
            onEdit: onEditPlace,
            onRemove: onRemovePlace,
          ),
      ],
    );
  }
}

class _AttachmentActionRow extends StatelessWidget {
  const _AttachmentActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: colors.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing ??
                Icon(
                  CupertinoIcons.chevron_forward,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({
    required this.image,
    required this.preparing,
    required this.enabled,
    required this.onChange,
    required this.onRemove,
  });

  final PreparedImage image;
  final bool preparing;
  final bool enabled;
  final VoidCallback onChange;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      key: const Key('forum-photo-preview'),
      image: true,
      label: 'Selected community post photo',
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              image.bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => ColoredBox(
                color: colors.surfaceContainerHighest,
                child: Icon(
                  CupertinoIcons.photo,
                  size: 42,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xB8000000)],
                  stops: [0.55, 1],
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton.filled(
                key: const Key('forum-remove-photo'),
                tooltip: 'Remove photo',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xB8000000),
                  foregroundColor: Colors.white,
                ),
                onPressed: enabled && !preparing ? onRemove : null,
                icon: const Icon(CupertinoIcons.xmark, size: 18),
              ),
            ),
            Positioned(
              left: 14,
              right: 10,
              bottom: 10,
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Ready to share',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('forum-change-photo'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: enabled && !preparing ? onChange : null,
                    icon: const Icon(
                      CupertinoIcons.arrow_2_circlepath,
                      size: 16,
                    ),
                    label: const Text('Change'),
                  ),
                ],
              ),
            ),
            if (preparing)
              const ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: CupertinoActivityIndicator(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectedPlace extends StatelessWidget {
  const _SelectedPlace({
    required this.name,
    required this.address,
    required this.enabled,
    required this.onEdit,
    required this.onRemove,
  });

  final String name;
  final String address;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('forum-selected-place'),
      color: colors.primaryContainer.withValues(alpha: 0.36),
      padding: const EdgeInsets.fromLTRB(14, 10, 5, 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              CupertinoIcons.location_fill,
              size: 20,
              color: colors.onPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('forum-edit-place'),
            tooltip: 'Edit public place',
            onPressed: enabled ? onEdit : null,
            icon: const Icon(CupertinoIcons.pencil, size: 19),
          ),
          IconButton(
            key: const Key('forum-remove-place'),
            tooltip: 'Remove public place',
            onPressed: enabled ? onRemove : null,
            icon: const Icon(CupertinoIcons.trash, size: 19),
          ),
        ],
      ),
    );
  }
}

class _PlaceDraft {
  const _PlaceDraft({required this.name, required this.address});

  final String name;
  final String address;
}

class _PlaceEditorSheet extends StatefulWidget {
  const _PlaceEditorSheet({
    required this.repository,
    this.initialName,
    this.initialAddress,
  });

  final PlaceRepository repository;
  final String? initialName;
  final String? initialAddress;

  @override
  State<_PlaceEditorSheet> createState() => _PlaceEditorSheetState();
}

class _PlaceEditorSheetState extends State<_PlaceEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _address = TextEditingController(text: widget.initialAddress);
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final length = value?.trim().length ?? 0;
    if (length < 2) return 'Use at least 2 characters.';
    if (length > 120) return 'Use 120 characters or fewer.';
    return null;
  }

  String? _validateAddress(String? value) {
    final length = value?.trim().length ?? 0;
    if (length < 3) return 'Use at least 3 characters.';
    if (length > 300) return 'Use 300 characters or fewer.';
    return null;
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(
      context,
    ).pop(_PlaceDraft(name: _name.text.trim(), address: _address.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.initialName == null
                    ? 'Tag a public place'
                    : 'Edit public place',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Help neighbours recognise where the photo or conversation is about.',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              TextFormField(
                key: const Key('forum-place-name'),
                controller: _name,
                autofocus: widget.initialName == null,
                maxLength: 120,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Place name',
                  hintText: 'Community garden, café, park…',
                  prefixIcon: Icon(CupertinoIcons.building_2_fill),
                  counterText: '',
                ),
                validator: _validateName,
              ),
              const SizedBox(height: 12),
              PlaceAutocompleteField(
                fieldKey: const Key('forum-place-address'),
                controller: _address,
                repository: widget.repository,
                onTextChanged: () {},
                onSelected: (place) {
                  final venueName = place.suggestedVenueName;
                  if (_name.text.trim().isEmpty && venueName != null) {
                    _name.text = venueName;
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Public address',
                  hintText: 'Search for a venue or address',
                  prefixIcon: Icon(CupertinoIcons.map_pin_ellipse),
                  counterText: '',
                ),
                validator: _validateAddress,
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: colors.errorContainer.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      CupertinoIcons.shield_lefthalf_fill,
                      color: colors.onErrorContainer,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Public places only. Never tag a home address or someone’s private location.',
                        style: TextStyle(
                          color: colors.onErrorContainer,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('forum-save-place'),
                  onPressed: _save,
                  icon: const Icon(CupertinoIcons.checkmark),
                  label: Text(
                    widget.initialName == null ? 'Add Place' : 'Save Place',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
