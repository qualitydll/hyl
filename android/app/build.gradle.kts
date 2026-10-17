import java.security.MessageDigest
import java.net.URL

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val mihomoAndroidVersion = "0.3.7"
val mihomoAndroidSha256 = "e9582440766f7e37f8f6b23344bee35d73e66e7e7a9fc3b90da5631f0fd19f24"
val mihomoAndroidAar = layout.buildDirectory.file(
    "mihomo/libmihomo-android-v$mihomoAndroidVersion.aar",
)
val downloadMihomoAndroid by tasks.registering {
    inputs.property("mihomoAndroidVersion", mihomoAndroidVersion)
    inputs.property("mihomoAndroidSha256", mihomoAndroidSha256)
    outputs.file(mihomoAndroidAar)

    doLast {
        val target = mihomoAndroidAar.get().asFile
        target.parentFile.mkdirs()
        val url =
            "https://github.com/oviron/libmihomo-android/releases/download/" +
                "v$mihomoAndroidVersion/libmihomo-android-v$mihomoAndroidVersion.aar"
        URL(url).openStream().use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        }
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(target.readBytes())
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
        check(digest == mihomoAndroidSha256) {
            "Mihomo Android library checksum mismatch: expected $mihomoAndroidSha256, got $digest"
        }
    }
}

android {
    namespace = "dev.crew.crew"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.crew.crew"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // The bundled Mihomo AAR contains multiple ABIs; ship ARM64 only.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            // The Mihomo AAR ships several ABIs; exclude unused native libraries from the APK.
            excludes += setOf("lib/armeabi-v7a/**", "lib/x86/**", "lib/x86_64/**")
        }
    }

    buildTypes {
        release {
            // TODO: Configure a private release signing key before publishing.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    implementation(files(mihomoAndroidAar).builtBy(downloadMihomoAndroid))
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
