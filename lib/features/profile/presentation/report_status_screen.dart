import 'package:flutter/material.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/member_controls.dart';

class ReportStatusScreen extends StatelessWidget {
  const ReportStatusScreen({required this.repository, super.key});

  final ProfileRepository repository;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your reports')),
    body: FutureBuilder<List<MemberReport>>(
      future: repository.ownReports(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load report statuses.'));
        }
        final reports = snapshot.data ?? const [];
        if (reports.isEmpty) {
          return const Center(
            child: Text('You have not submitted any reports.'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: reports.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final report = reports[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(report.title),
              subtitle: Text(
                '${report.reason.replaceAll('_', ' ')} · ${report.kind.replaceAll('_', ' ')}',
              ),
              trailing: Chip(label: Text(report.status)),
            );
          },
        );
      },
    ),
  );
}
