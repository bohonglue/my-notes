import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.bohong.my_notes"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.bohong.my_notes"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 固定的簽章金鑰：每次打包的 APK 簽章一樣，新版才能直接覆蓋安裝舊版（資料不會被清掉）。
    // 金鑰由 GitHub Actions 從 secrets 帶入（ANDROID_KEYSTORE_BASE64、ANDROID_KEYSTORE_PASSWORD）；
    // 沒有設定時退回 debug 金鑰（每次打包都不一樣，更新時要先移除舊版）。
    val keystoreB64 = System.getenv("ANDROID_KEYSTORE_BASE64").orEmpty()
    val keystorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD").orEmpty()
    val hasReleaseKey = keystoreB64.isNotBlank() && keystorePassword.isNotBlank()
    signingConfigs {
        create("release") {
            if (hasReleaseKey) {
                val f = layout.buildDirectory.file("release.jks").get().asFile
                f.parentFile.mkdirs()
                f.writeBytes(Base64.getMimeDecoder().decode(keystoreB64))
                storeFile = f
                storePassword = keystorePassword
                keyAlias = "mynotes"
                keyPassword = keystorePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
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
