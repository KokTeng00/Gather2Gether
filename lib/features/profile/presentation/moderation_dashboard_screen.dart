import 'package:flutter/material.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/member_controls.dart';

class ModerationDashboardScreen extends StatefulWidget {
  const ModerationDashboardScreen({required this.repository, super.key});

  final ProfileRepository repository;

  @override
  State<ModerationDashboardScreen> createState() =>
      _ModerationDashboardScreenState();
}

class _ModerationDashboardScreenState extends State<ModerationDashboardScreen> {
  List<ModerationReport>? _reports;
  Map<String, int> _overview = const {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.repository.moderationReports(),
        widget.repository.moderationOverview(),
      ]);
      if (!mounted) return;
      setState(() {
        _reports = results[0] as List<ModerationReport>;
        _overview = results[1] as Map<String, int>;
      });
    } catch (_) {
      if (mounted) setState(() => _reports = const []);
    }
  }

  Future<void> _triage() async {
    setState(() => _busy = true);
    try {
      final priorities = await widget.repository.triageReports();
      if (!mounted) return;
      setState(
        () => _reports = _reports
            ?.map((report) {
              final result = priorities[report.id];
              return result == null
                  ? report
                  : report.withPriority(result.priority, result.reason);
            })
            .toList(growable: false),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI triage is unavailable right now.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(
    ModerationReport report,
    String action, {
    String note = '',
  }) async {
    setState(() => _busy = true);
    try {
      await widget.repository.moderateReport(
        reportKind: report.kind,
        reportId: report.id,
        action: action,
        note: note,
      );
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this report.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmHide(ModerationReport report) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const _ModerationNoteDialog(),
    );
    if (note != null && mounted) {
      await _act(report, 'hidden', note: note);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reports = _reports;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moderation'),
        actions: [
          IconButton(
            tooltip: 'Prioritize with AI',
            onPressed: _busy || reports?.isEmpty != false ? null : _triage,
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
        ],
      ),
      body: reports == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(label: Text('${_overview['open'] ?? 0} open')),
                      Chip(
                        label: Text('${_overview['reviewing'] ?? 0} reviewing'),
                      ),
                      Chip(
                        label: Text(
                          '${_overview['resolved_today'] ?? 0} handled today',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (reports.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No open reports.')),
                    ),
                  for (final report in reports)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    report.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                                if (report.priority != null)
                                  Chip(label: Text(report.priority!)),
                              ],
                            ),
                            Text(
                              '${report.kind.replaceAll('_', ' ')} · ${report.reason.replaceAll('_', ' ')}',
                            ),
                            if (report.excerpt.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(report.excerpt),
                            ],
                            if (report.priorityReason != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                report.priorityReason!,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _act(report, 'reviewing'),
                                  child: const Text('Reviewing'),
                                ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _act(report, 'dismissed'),
                                  child: const Text('Dismiss'),
                                ),
                                FilledButton.tonal(
                                  onPressed: _busy
                                      ? null
                                      : () => _confirmHide(report),
                                  child: const Text('Hide & resolve'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _ModerationNoteDialog extends StatefulWidget {
  const _ModerationNoteDialog();

  @override
  State<_ModerationNoteDialog> createState() => _ModerationNoteDialogState();
}

class _ModerationNoteDialogState extends State<_ModerationNoteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() == true) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Hide reported content?'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _controller,
        maxLength: 1000,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Audit note',
          hintText: 'Why this action is needed',
        ),
        validator: (value) => value == null || value.trim().isEmpty
            ? 'Add a short reason for the audit trail.'
            : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Hide & resolve')),
    ],
  );
}
