class AppConfig {
  const AppConfig._();

  static const authCallbackUrl = 'gather2gether://login-callback';

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const edgeApiUrl = String.fromEnvironment(
    'EDGE_API_URL',
    defaultValue: 'https://gather2gether.pages.dev/api/v1',
  );
  static const mapStyleUrl = String.fromEnvironment(
    'MAP_STYLE_URL',
    defaultValue: 'https://tiles.openfreemap.org/styles/liberty',
  );

  static bool get isConfigured =>
      Uri.tryParse(supabaseUrl)?.hasScheme == true &&
      supabasePublishableKey.trim().isNotEmpty &&
      Uri.tryParse(edgeApiUrl)?.hasScheme == true;
}
