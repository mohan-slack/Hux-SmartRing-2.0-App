import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: the UPLOAD key lives in android/key.properties +
// a .jks file, both git-ignored (see android/key.properties.example and
// docs/release/SIGNING.md). Google Play re-signs with the app signing key.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "in.co.hux.hux_app"
    // flutter_local_notifications 21+ compiles against API 36.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Desugaring: required by flutter_local_notifications for
        // scheduled notifications on older Android versions.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        multiDexEnabled = true
        // PERMANENT once published on Google Play — never change it.
        applicationId = "in.co.hux.hux_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Health Connect (health ^13) requires API 26+. Flutter's default
        // (21/24) lets the build pass but Health Connect fails at runtime.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKey) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // No key.properties: debug-signed so `flutter run --release`
                // still works locally. Play Console REJECTS this build —
                // create the upload key first (docs/release/SIGNING.md).
                logger.warn("HUX: android/key.properties not found — release build is DEBUG-signed (not uploadable).")
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
