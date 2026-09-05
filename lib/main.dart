import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/appearance_controller.dart';
import 'package:gather2gether/app.dart';
import 'package:gather2gether/config/app_config.dart';
import 'package:gather2gether/core/security/secure_auth_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppearanceController.instance.load();

  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(
        localStorage: SecureSessionStorage(),
        pkceAsyncStorage: SecurePkceStorage(),
      ),
    );
  }

  runApp(Gather2GetherApp(isConfigured: AppConfig.isConfigured));
}
