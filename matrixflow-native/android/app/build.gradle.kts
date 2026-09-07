plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.matrixflow.matrixflow_native"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.0.12433566"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.matrixflow.matrixflow_native"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
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

// In Flutter, when building with `--no-pub`, Flutter skips regenerating GeneratedPluginRegistrant.java
// (due to `if (!shouldRunPub) return;` in Flutter SDK's `regeneratePlatformSpecificToolingIfApplicable`).
// If a prior `flutter pub get` or `flutter test` generated the registrant in debug mode, it contains
// `dev.flutter.plugins.integration_test.IntegrationTestPlugin`. However, Gradle strips dev_dependencies
// from release builds, causing javac to fail on the missing package.
// This task cleans up dev-only plugins from GeneratedPluginRegistrant.java during release builds.
tasks.register("cleanDevPluginsFromReleaseRegistrant") {
    doLast {
        val registrantFile = file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
        if (registrantFile.exists()) {
            val content = registrantFile.readText()
            if (content.contains("dev.flutter.plugins.integration_test.IntegrationTestPlugin")) {
                val cleaned = content.replace(
                    Regex("""\r?\n\s*try\s*\{\s*flutterEngine\.getPlugins\(\)\.add\(new dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin\(\)\);\s*\}\s*catch\s*\(Exception e\)\s*\{\s*Log\.e\(TAG,\s*"Error registering plugin integration_test[^"]*",\s*e\);\s*\}"""),
                    ""
                )
                if (cleaned != content) {
                    registrantFile.writeText(cleaned)
                    logger.lifecycle("Cleaned integration_test dev plugin from GeneratedPluginRegistrant.java for release build.")
                }
            }
        }
    }
}

tasks.matching { it.name == "preReleaseBuild" || it.name == "compileReleaseJavaWithJavac" }.configureEach {
    dependsOn("cleanDevPluginsFromReleaseRegistrant")
}
