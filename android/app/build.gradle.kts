import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun releaseSigningValue(propertyName: String, environmentName: String): String? =
    keystoreProperties.getProperty(propertyName)
        ?: providers.gradleProperty(propertyName).orNull
        ?: providers.environmentVariable(environmentName).orNull

val releaseStoreFile = releaseSigningValue("storeFile", "ANDROID_STORE_FILE")
val releaseStorePassword = releaseSigningValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = releaseSigningValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = releaseSigningValue("keyPassword", "ANDROID_KEY_PASSWORD")

android {
    namespace = "com.rehtt.foxlingo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.rehtt.foxlingo"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            releaseStoreFile?.takeIf { it.isNotBlank() }?.let {
                storeFile = file(it)
            }
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

gradle.taskGraph.whenReady {
    val needsReleaseSigning = allTasks.any { it.name.contains("Release", ignoreCase = true) }
    if (needsReleaseSigning) {
        val missingSigningValues = mutableListOf<String>()
        if (releaseStoreFile.isNullOrBlank()) missingSigningValues.add("storeFile")
        if (releaseStorePassword.isNullOrBlank()) missingSigningValues.add("storePassword")
        if (releaseKeyAlias.isNullOrBlank()) missingSigningValues.add("keyAlias")
        if (releaseKeyPassword.isNullOrBlank()) missingSigningValues.add("keyPassword")

        if (missingSigningValues.isNotEmpty()) {
            throw GradleException(
                "Missing Android release signing configuration: ${missingSigningValues.joinToString()}. " +
                    "Set android/key.properties or CI secrets before building release artifacts."
            )
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

dependencies {
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
}
