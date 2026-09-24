plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val cnkhStorePath = System.getenv("CNKH_ANDROID_KEYSTORE_PATH")
val cnkhStorePassword = System.getenv("CNKH_ANDROID_KEYSTORE_PASSWORD")
val cnkhKeyAlias = System.getenv("CNKH_ANDROID_KEY_ALIAS")
val cnkhKeyPassword = System.getenv("CNKH_ANDROID_KEY_PASSWORD")
val cnkhReleaseSigningReady = listOf(
    cnkhStorePath,
    cnkhStorePassword,
    cnkhKeyAlias,
    cnkhKeyPassword,
).all { !it.isNullOrBlank() }
val cnkhAllowDebugRelease = System.getenv("CNKH_ALLOW_DEBUG_RELEASE") == "true"
val cnkhReleaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (cnkhReleaseTaskRequested && !cnkhReleaseSigningReady && !cnkhAllowDebugRelease) {
    throw GradleException(
        "Release APK signing is not configured. Provide the CNKH_ANDROID_KEYSTORE_* environment variables.",
    )
}

android {
    namespace = "com.cnkh.cnkh_pos_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.cnkh.cnkh_pos_mobile"
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (cnkhReleaseSigningReady) {
            create("cnkhRelease") {
                storeFile = file(cnkhStorePath!!)
                storePassword = cnkhStorePassword
                keyAlias = cnkhKeyAlias
                keyPassword = cnkhKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                cnkhReleaseSigningReady -> signingConfigs.getByName("cnkhRelease")
                cnkhAllowDebugRelease -> signingConfigs.getByName("debug")
                else -> null
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    // Chinese model also recognizes Latin text, so one bundled recognizer covers
    // the Chinese/English supplier invoices used by CNKH POS.
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
}

flutter {
    source = "../.."
}
