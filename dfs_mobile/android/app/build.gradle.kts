// android/app/build.gradle.kts

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "de.dfs_diamon.dfs_complaints"
    compileSdk = 34

    defaultConfig {
        applicationId = "de.dfs_diamon.dfs_complaints" // <- deine Paketkennung
        minSdk = 21
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
    }

    // Signierung via key.properties (falls vorhanden)
    signingConfigs {
        create("release") {
            val keystoreProps = java.util.Properties()
            val kpFile = rootProject.file("key.properties")
            if (kpFile.exists()) {
                keystoreProps.load(java.io.FileInputStream(kpFile))
                storeFile = file(keystoreProps["storeFile"] as String)
                storePassword = keystoreProps["storePassword"] as String
                keyAlias = keystoreProps["keyAlias"] as String
                keyPassword = keystoreProps["keyPassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
            // ProGuard bei Bedarf:
            // proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        getByName("debug") {
            // optional debug-spezifisches
        }
    }
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib:1.9.24")
}
