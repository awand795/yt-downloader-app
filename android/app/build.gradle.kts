plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ytdlp.yt_downloader"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ytdlp.yt_downloader"
        // youtubedl-android (the bundled yt-dlp engine) requires API 24.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        // The bundled Python + ffmpeg binaries are loaded from the APK's lib
        // directory by youtubedl-android, so they must not be page-aligned only.
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // Signed with the debug key so `flutter build apk --release` works out
            // of the box. Replace with a real keystore before publishing.
            signingConfig = signingConfigs.getByName("debug")
            // youtubedl-android resolves several classes reflectively; R8 renaming
            // them aborts the engine with "class ... is not a concrete class".
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    // yt-dlp + bundled Python and ffmpeg, executed on device.
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1")
}

flutter {
    source = "../.."
}
