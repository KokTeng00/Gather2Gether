import java.util.Properties
import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val uploadProperties = Properties().apply {
    val propertiesFile = rootProject.file("key.properties")
    if (propertiesFile.exists()) propertiesFile.inputStream().use { load(it) }
}
fun uploadSetting(environment: String, property: String): String? =
    System.getenv(environment)?.takeIf { it.isNotBlank() }
        ?: uploadProperties.getProperty(property)?.takeIf { it.isNotBlank() }

val uploadStore = uploadSetting("ANDROID_KEYSTORE_PATH", "storeFile")
val uploadStorePassword = uploadSetting("ANDROID_KEYSTORE_PASSWORD", "storePassword")
val uploadAlias = uploadSetting("ANDROID_KEY_ALIAS", "keyAlias")
val uploadKeyPassword = uploadSetting("ANDROID_KEY_PASSWORD", "keyPassword")
val uploadSigningReady = listOf(uploadStore, uploadStorePassword, uploadAlias, uploadKeyPassword)
    .all { it != null }

val appDefines = (project.findProperty("dart-defines") as? String).orEmpty()
    .split(',').filter { it.isNotBlank() }.associate { encoded ->
        val parts = String(Base64.getDecoder().decode(encoded), Charsets.UTF_8).split('=', limit = 2)
        parts[0] to parts.getOrElse(1) { "" }
    }

android {
    namespace = "com.gather2gether.gather2gether"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.gather2gether.gather2gether"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // image_picker 1.2+ supports Android SDK 24 and newer.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Firebase must also initialize when a notification starts the Android
        // process before Flutter runs. Use the same configuration as Dart.
        if (appDefines["REMOTE_PUSH_ENABLED"] == "true") {
            mapOf(
                "google_app_id" to "FIREBASE_ANDROID_APP_ID",
                "google_api_key" to "FIREBASE_ANDROID_API_KEY",
                "gcm_defaultSenderId" to "FIREBASE_MESSAGING_SENDER_ID",
                "project_id" to "FIREBASE_PROJECT_ID",
            ).forEach { (resource, define) ->
                val value = appDefines[define]
                check(!value.isNullOrBlank()) { "Remote push requires $define." }
                resValue("string", resource, value)
            }
        }
    }

    signingConfigs {
        if (uploadSigningReady) {
            create("release") {
                storeFile = rootProject.file(uploadStore!!)
                storePassword = uploadStorePassword
                keyAlias = uploadAlias
                keyPassword = uploadKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (uploadSigningReady) signingConfig = signingConfigs.getByName("release")
        }
    }
}

// Debug development remains available; release builds must never use debug keys.
tasks.configureEach {
    if (name == "preReleaseBuild") {
        doFirst {
            check(uploadSigningReady && rootProject.file(uploadStore!!).isFile) {
                "Release signing is missing. Run python3 scripts/prepare_android_signing.py " +
                    "or configure the ANDROID_KEYSTORE_* and ANDROID_KEY_* environment variables."
            }
        }
    }
}

flutter {
    source = "../.."
}
