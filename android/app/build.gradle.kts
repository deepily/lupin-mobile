plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase Cloud Messaging (FCM) — processes android/app/google-services.json.
    // Safe to apply only because google-services.json is present (applying it without
    // the JSON breaks every build; see runbook 92 step 2).
    id("com.google.gms.google-services")
}

android {
    namespace = "ai.deepily.lupin_mobile"
    // Pinned ABOVE Flutter's default of 35 (FlutterExtension.kt:23), because
    // flutter_tts asks for 36 and the build says so on every run (row 5cbd2e42,
    // seen on Rick's first deploy --build). The platform is already installed
    // at ~/Android/Sdk/platforms/android-36.
    //
    // ⚠️ AGP HERE IS 8.7.3 (settings.gradle.kts:21), WHICH WAS TESTED UP TO
    // compileSdk 35. AGP warns when compileSdk exceeds what it was tested
    // against, so this may TRADE the flutter_tts warning for an AGP one rather
    // than removing a line from the build log. Whether it does cannot be
    // established from a worktree — the google-services plugin is applied
    // (build.gradle.kts:9) and needs the gitignored google-services.json, so no
    // Gradle configuration runs here at all. Verified by a main-checkout build,
    // not by this commit.
    compileSdk = 36
    // Pinned ABOVE Flutter's default of 26.3.11579264 (FlutterExtension.kt:41),
    // because 19 plugins ask for 27.0.12077973 and the build says so every run
    // (row 5cbd2e42).
    //
    // 🔴 DO NOT MERGE THIS COMMIT UNTIL THE NDK IS ACTUALLY INSTALLED. Unlike
    // compileSdk 36, whose platform is already on the server, NDK 27.0.12077973
    // is NOT present — ~/Android/Sdk/ndk holds only 26.3.11579264. Pinning a
    // version that is not there does not degrade to a warning; it fails the
    // build, for every seat, since all of them share that one SDK
    // (~/.config/flutter/settings, android/local.properties). Merged ahead of the
    // install, this line stops the APK the operator is waiting on.
    //
    // The install, which needs an operator/manager word because the SDK is
    // shared and peer Gradle daemons are live:
    //   ~/Android/Sdk/cmdline-tools/latest/bin/sdkmanager "ndk;27.0.12077973"
    // Additive — 26.3 stays, so nothing already building breaks by installing.
    // Order matters: install FIRST, then merge this, or there is a window where
    // the pin points at a missing NDK.
    ndkVersion = "27.0.12077973"

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
