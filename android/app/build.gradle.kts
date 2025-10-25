import java.util.Properties // Make sure this import line is at the very top

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// --- This block reads your key.properties file ---
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties") // Assumes key.properties is in the 'android' folder
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
// --- End block ---

android {
    // --- Use your original namespace here if it was different ---
    namespace = "com.shriyakjain.debtledger"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // --- Updated Java Version ---
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        // --- Updated Kotlin JVM Target ---
        jvmTarget = "17"
    }

    // --- Defines the signing configurations ---
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            // Updated to handle potential null storeFile path safely
            storeFile = if (keystoreProperties["storeFile"] != null && keystoreProperties["storeFile"].toString().isNotEmpty()) {
                file(keystoreProperties["storeFile"] as String)
            } else {
                null
            }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
    // --- End signingConfigs block ---

    defaultConfig {
        // --- Use your original application ID here if it was different ---
        applicationId = "com.shriyakjain.debtledger" // Or "com.example.debtledger"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("release") {
            // --- Corrected signing config ---
            signingConfig = signingConfigs.getByName("release")
            // You might add other release settings here later, like:
            // isMinifyEnabled = true
            // isShrinkResources = true
            // proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}
