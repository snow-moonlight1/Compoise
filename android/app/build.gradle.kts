import java.util.Properties
import java.util.Base64
import java.io.FileInputStream
import java.io.File
import java.security.MessageDigest
import groovy.json.JsonSlurper

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
// Opt-in, private validation identity. The normal applicationId is unchanged.
val wp17Validation = wp17ExternalPath("wp17OcrValidation") == "true"
val wp17Models = wp17ExternalPath("wp17OcrModels")
// I8 compile/packaging checks deliberately produce unsigned APKs. This is an
// explicit local opt-in and cannot satisfy the formal signing gate below.
val wp17I8Unsigned = wp17ExternalPath("wp17I8Unsigned") == "true"
val wp17I8Abi = wp17ExternalPath("wp17I8Abi")
check(wp17I8Abi == null || (wp17I8Unsigned && wp17Models != null &&
    wp17I8Abi in listOf("x86_64", "arm64-v8a"))) { "I8 ABI requires an unsigned official OCR packaging check" }
if (wp17Models != null) {
    check(wp17OcrEnabled) { "Official OCR assets require the native OCR component" }
    val root = file(wp17Models).resolve("wp17-ocr")
    val json = JsonSlurper()
    val manifest = json.parse(root.resolve("bundle-manifest.json")) as Map<*, *>
    val deployment = json.parse(root.resolve("deployed.json")) as Map<*, *>
    val lock = json.parse(file("../../native/ocr/tools/models.lock.json")) as Map<*, *>
    check(manifest["modelSource"] == "official" && deployment["modelSource"] == "official")
    check(deployment["conversion"] == lock["conversion"]) { "Unreviewed conversion provenance" }
    val files = manifest["files"] as Map<*, *>
    val locked = lock["files"] as Map<*, *>
    val attachments = lock["attachments"] as Map<*, *>
    val expected = mutableMapOf<String, String>()
    for (kind in listOf("det", "rec")) for (suffix in listOf("param", "bin")) {
        val name = "PP_OCRv5_mobile_$kind.ncnn.$suffix"
        expected["ncnn/$name"] = (locked["ncnn-official/$name"] as Map<*, *>)["sha256"] as String
    }
    expected["ncnn/ppocrv5_dict.txt"] = "d1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b"
    for ((name, record) in attachments) expected[name as String] = (record as Map<*, *>)["sha256"] as String
    check(files.keys == expected.keys + setOf("deployed.json", "licenses/THIRD_PARTY_OCR_NOTICES.md"))
    for ((rawName, rawRecord) in files) {
        val name = rawName as String
        val record = rawRecord as Map<*, *>
        val data = root.resolve(name)
        val digest = MessageDigest.getInstance("SHA-256").digest(data.readBytes())
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        check(data.length() == (record["bytes"] as Number).toLong() && digest == record["sha256"])
        check(expected[name] == null || digest == expected[name]) { "Official asset pin mismatch: $name" }
    }
}
val hasKeystore = keystorePropertiesFile != null
if (hasKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile!!))
}

// Isolated identity for the opt-in WP15-D2 device entry. No effect on normal
// debug/release builds, signing or the production applicationId.
val wp15D2Device = (project.findProperty("dart-defines") as? String)
    ?.split(",")?.any {
        String(Base64.getDecoder().decode(it)) == "WP15_D2_DEVICE=true"
    } == true

check(!(wp15D2Device && wp17Validation)) {
    "WP15-D2 and WP17-I6 validation identities cannot be combined"
}
check(!(wp17I8Unsigned && (wp15D2Device || wp17Validation))) {
    "I8 candidates cannot use a diagnostic application identity"
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
            ndk { abiFilters.addAll(if (wp17I8Abi != null) listOf(wp17I8Abi) else listOf("x86_64", "arm64-v8a")) }
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
        debug {
            if (wp15D2Device) applicationIdSuffix = ".wp15d2"
            else if (wp17Validation) applicationIdSuffix = ".wp17i6"
        }
        release {
            val releaseSigning = signingConfigs.getByName("release")
            if (wp17I8Unsigned) {
                signingConfig = null
            } else if (releaseSigning.storeFile != null && releaseSigning.storeFile!!.exists()) {
                signingConfig = releaseSigning
            } else {
                // Keyless debug and PR builds keep the debug key. Formal release
                // sets REQUIRE_RELEASE_SIGNING and fails in verifyFormalReleaseSigning.
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
    if (wp17Models != null) sourceSets.getByName("main").assets.srcDir(file(wp17Models))
}

if (wp17Validation) {
    tasks.matching { it.name.contains("Release") }.configureEach {
        doFirst { error("wp17OcrValidation is debug-only; use the dedicated debug package") }
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
        check(!wp17I8Unsigned) { "Unsigned I8 packaging checks cannot be formal release candidates" }
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
