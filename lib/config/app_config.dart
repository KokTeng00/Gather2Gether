class AppConfig {
  const AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const edgeApiUrl = String.fromEnvironment(
    'EDGE_API_URL',
    defaultValue: 'https://gather2gether.pages.dev/api/v1',
  );

  static bool get isConfigured =>
      Uri.tryParse(supabaseUrl)?.hasScheme == true &&
      supabasePublishableKey.trim().isNotEmpty &&
      Uri.tryParse(edgeApiUrl)?.hasScheme == true;
}
