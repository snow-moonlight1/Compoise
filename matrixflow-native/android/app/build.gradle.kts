import java.util.Properties
import java.io.FileInputStream
import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = listOf(
    rootProject.file("key.properties"),
    rootProject.file("keystore.properties"),
    project.file("key.properties"),
    project.file("keystore.properties")
).firstOrNull { it.exists() }

val keystoreProperties = Properties()
val hasKeystore = keystorePropertiesFile != null
if (hasKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile!!))
}

android {
    namespace = "com.matrixflow.matrixflow_native"
    compileSdk = 36 // flutter_secure_storage 10.3.4 compiles against API 36.
    ndkVersion = "28.0.12433566"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.matrixflow.app"
        minSdk = 23 // flutter_secure_storage 10.x requires Android 6.0+.
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasKeystore) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                val rawStoreFile = keystoreProperties.getProperty("storeFile")
                if (rawStoreFile != null) {
                    val candidate = file(rawStoreFile)
                    storeFile = if (candidate.exists()) candidate else File(keystorePropertiesFile!!.parentFile, rawStoreFile)
                }
                storePassword = keystoreProperties.getProperty("storePassword")
            } else if (System.getenv("ANDROID_KEYSTORE_PATH") != null) {
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
                storeFile = file(System.getenv("ANDROID_KEYSTORE_PATH"))
                storePassword = System.getenv("ANDROID_STORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            val releaseSigning = signingConfigs.getByName("release")
            if (releaseSigning.storeFile != null && releaseSigning.storeFile!!.exists()) {
                signingConfig = releaseSigning
            } else {
                // Keyless debug and PR builds keep the debug key. Formal release
                // sets REQUIRE_RELEASE_SIGNING and fails in verifyFormalReleaseSigning.
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

// Configuration must stay silent when CI=true. Only a release task that opts in
// with REQUIRE_RELEASE_SIGNING=true refuses a missing keystore.
tasks.register("verifyFormalReleaseSigning") {
    doLast {
        if (System.getenv("REQUIRE_RELEASE_SIGNING") != "true") {
            return@doLast
        }
        val store = android.signingConfigs.findByName("release")?.storeFile
        if (store == null || !store.exists()) {
            throw GradleException(
                "Formal release signing credentials are required. " +
                    "Refusing to publish a debug-signed APK.",
            )
        }
    }
}

tasks.matching {
    it.name == "preReleaseBuild" ||
        it.name == "assembleRelease" ||
        it.name == "bundleRelease"
}.configureEach {
    dependsOn("verifyFormalReleaseSigning")
}
