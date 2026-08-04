import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials, kept out of the repository.
//
// See `key.properties.example` for the shape of the file, and note that the
// SHA-256 fingerprint that goes into `web/public/.well-known/assetlinks.json`
// is NOT the one from this keystore — Play App Signing re-signs the upload, so
// the value has to come from Play Console → Setup → App signing.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.timedrop.timedrop_mobile"
    // Several plugins (camera, geolocator, image_picker, video_player, …)
    // require compiling against SDK 36; geocoding needs 34+. 36 satisfies all.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (uses java.time APIs on
        // API levels below 26).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.timedrop.timedrop_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Without key.properties this used to fall back to the DEBUG keystore,
            // which is the dangerous shape of this problem: the build succeeds, the
            // artifact looks fine, and you only find out at the Play upload — or
            // worse, after publishing an App Link fingerprint that will never
            // match. Failing here instead makes the missing keystore impossible
            // to miss.
            //
            // `flutter run --release` on a device is deliberately still allowed to
            // use the debug keystore; it is `assemble`/`bundle` that must not.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Guards the artifacts that actually leave this machine. A locally-run release
// build is fine unsigned-for-real; an AAB or a distributable APK is not.
gradle.taskGraph.whenReady {
    if (hasReleaseKeystore) return@whenReady
    val shipping = allTasks.any { task ->
        task.name.startsWith("bundle") && task.name.contains("Release") ||
            task.name == "assembleRelease"
    }
    if (shipping) {
        throw GradleException(
            "Release signing is not configured: android/key.properties is missing.\n" +
                "Copy android/key.properties.example, create a keystore, and fill it in.\n" +
                "Building this way would sign with the debug key, which the Play " +
                "Store rejects and which would produce an App Link fingerprint " +
                "that never verifies."
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
