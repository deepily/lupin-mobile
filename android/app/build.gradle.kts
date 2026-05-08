plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ai.deepily.lupin_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by `flutter_local_notifications` ^17.2.3 (resolves 17.2.4) —
        // its WorkManager + Android-X scheduling APIs use Java 8+ stdlib classes
        // (java.time.*) that need desugaring on minSdk 24. See:
        // https://developer.android.com/studio/write/java8-support
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ai.deepily.lupin_mobile"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Companion to `isCoreLibraryDesugaringEnabled = true` above. 2.1.4 is the
    // current stable as of 2026 and is compatible with both flutter_local_notifications
    // 17.x and 18.x. Bump only if a future plugin requires it.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
