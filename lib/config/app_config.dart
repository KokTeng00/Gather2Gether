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
  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const firebaseAndroidApiKey = String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
  );
  static const firebaseAndroidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );
  static const firebaseIosApiKey = String.fromEnvironment(
    'FIREBASE_IOS_API_KEY',
  );
  static const firebaseIosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const firebaseIosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
    defaultValue: 'com.gather2gether.gather2gether',
  );

  static bool get isConfigured =>
      Uri.tryParse(supabaseUrl)?.hasScheme == true &&
      supabasePublishableKey.trim().isNotEmpty &&
      Uri.tryParse(edgeApiUrl)?.hasScheme == true;
}
