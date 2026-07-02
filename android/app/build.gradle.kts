plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.roommodes.room_mode_calculator"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
