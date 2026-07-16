import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is configured out-of-repo: android/key.properties (git-
// ignored) holds the keystore path and passwords. Checkouts without it still
// build — release falls back to debug signing, which is fine for everything
// except an actual Play upload. The release workflow
// (.github/workflows/release.yml) materializes key.properties from secrets.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.roommodes.room_mode_calculator"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.roommodes.room_mode_calculator"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                arguments += listOf("-DANDROID_STL=c++_shared")
            }
        }
        // No ndk.abiFilters here: `flutter build apk --split-per-abi` (see
        // the CI workflow) configures its own `splits.abi` block, and Gradle
        // rejects having both set at once ("Conflicting configuration").
        // Leaving ABI selection unset lets the native library follow
        // whichever ABI(s) the surrounding app build already targets.
    }

    // Builds the native room-mode solver (../../native) via the same
    // CMakeLists.txt used for the standalone host build/tests -- see
    // native/README.md. The test executables in that file are skipped here
    // (guarded behind `if(NOT ANDROID)`), only the shared library is built.
    externalNativeBuild {
        cmake {
            path = file("../../native/CMakeLists.txt")
        }
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
            // Real upload signing when key.properties is present; debug keys
            // otherwise so `flutter run --release` still works anywhere.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
            )
            // Diagnostic escape hatch: NO_MINIFY=true builds a release APK
            // with R8 and resource shrinking off, to bisect shrinker-caused
            // crashes from everything else (see build.yml).
            if (System.getenv("NO_MINIFY") == "true") {
                isMinifyEnabled = false
                isShrinkResources = false
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
