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
val localMachineProperties = Properties()
val localMachinePropertiesFile = rootProject.file("local.properties")
if (localMachinePropertiesFile.exists()) {
    localMachinePropertiesFile.inputStream().use { localMachineProperties.load(it) }
}

// flutter build apk replaces the Gradle environment with JAVA_HOME and PATH,
// so ORG_GRADLE_PROJECT_* never arrives. local.properties is gitignored and
// is the channel that still reaches this file. Direct gradlew -P still works.
fun wp17ExternalPath(name: String): String? {
    val fromGradle = providers.gradleProperty(name).orNull?.trim()
    if (!fromGradle.isNullOrEmpty()) return fromGradle
    val fromLocal = localMachineProperties.getProperty(name)?.trim()
    if (fromLocal.isNullOrEmpty()) return null
    return fromLocal
}

val wp17NcnnRoot = wp17ExternalPath("wp17OcrNcnnRoot")
val wp17StbDir = wp17ExternalPath("wp17OcrStbDir")
val wp17OcrEnabled = wp17NcnnRoot != null && wp17StbDir != null
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
        if (wp17OcrEnabled) {
            ndk { abiFilters.addAll(listOf("x86_64", "arm64-v8a")) }
            externalNativeBuild {
                cmake {
                    arguments.addAll(listOf(
                        "-DWP17_NCNN_ROOT=${file(wp17NcnnRoot!!).absolutePath.replace('\\', '/')}",
                        "-DWP17_STB_DIR=${file(wp17StbDir!!).absolutePath.replace('\\', '/')}",
                        // The checked-in Android ncnn trees are static and were
                        // built against c++_static. AGP's default is c++_shared.
                        "-DANDROID_STL=c++_static",
                    ))
                }
            }
        }
    }

    if (wp17OcrEnabled) {
        externalNativeBuild {
            cmake {
                path = file("../../native/ocr/CMakeLists.txt")
                version = "3.22.1"
            }
        }
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
                    "Refusing to publish a debug-signed APK. " +
                "Provide android/key.properties (template: android/key.properties.example) " +
                    "or the ANDROID_KEYSTORE_PATH, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD and " +
                    "ANDROID_STORE_PASSWORD environment variables. See docs/DEVELOPMENT.md.",
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
