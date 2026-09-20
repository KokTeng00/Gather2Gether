class ModeratorVerification {
  const ModeratorVerification({required this.factorId, this.setupSecret});

  final String factorId;
  // Only held in the enrollment screen's memory; never logged or cached.
  final String? setupSecret;
}
