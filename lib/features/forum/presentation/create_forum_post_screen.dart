import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/constants/forum_constants.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';

class CreateForumPostScreen extends StatefulWidget {
  const CreateForumPostScreen({super.key, ForumRepository? repository})
    : _repository = repository;

  final ForumRepository? _repository;

  @override
  State<CreateForumPostScreen> createState() => _CreateForumPostScreenState();
}

class _CreateForumPostScreenState extends State<CreateForumPostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  late final ForumRepository _repository;
  String _category = forumCategories.first;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _repository = widget._repository ?? ForumRepository();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Discussion'),
        leading: IconButton(
          tooltip: 'Close',
          onPressed: _submitting ? null : () => Navigator.pop(context),
          icon: const Icon(CupertinoIcons.xmark),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              Text(
                'Start a conversation',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Ask something useful, share an idea, or find your people.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 26),
              AppSection(
                title: 'Discussion',
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(CupertinoIcons.square_grid_2x2),
                        hintText: 'Category',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      items: forumCategories
                          .map(
                            (category) => DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            ),
                          )
                          .toList(),
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _category = value!),
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
                        'Keep phone numbers, home addresses, and other private information out of public discussions.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const CupertinoActivityIndicator(color: Colors.white)
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
