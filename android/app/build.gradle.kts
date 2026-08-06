import java.util.zip.ZipEntry
import java.util.zip.ZipFile

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_application_1"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.flutter_application_1"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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

// The sqlite3 package's native-assets hook (configured in pubspec via
// `hooks.user_defines.sqlite3.source: sqlcipher`, needed only for the Windows
// desktop build) also downloads a raw libsqlcipher.so for the Android ABIs.
// sqflite_sqlcipher bundles its own SQLCipher native library through the
// net.zetetic AAR, whose libsqlcipher.so carries the Zetetic JNI
// (net.zetetic.database.sqlcipher.*) the plugin calls. Both share the file
// name libsqlcipher.so and the Flutter-staged sqlite3 build shadows the AAR's,
// causing UnsatisfiedLinkError at database open. Drop the staged raw copy so
// the AAR's remains the only libsqlcipher.so in the APK.
tasks.matching { it.name.startsWith("copyJniLibsflutterBuild") }.configureEach {
    doLast {
        val staged = outputs.files.singleFile
        staged.walkTopDown()
            .filter { it.isFile && it.name == "libsqlcipher.so" }
            .forEach { it.delete() }
    }
}

// Safety net: fail the build if a libsqlcipher.so without the Zetetic JNI ever
// reaches the APK again (e.g. the sqlite3 hook shadows the AAR's lib after a
// dependency upgrade). A silent wrong-lib only crashes at runtime on the device,
// so we fail loudly at build time instead.
fun verifySqlcipherJniInApk(apk: File) {
    val zip = ZipFile(apk)
    try {
        val offenders = zip.entries().asSequence()
            .filter { it.name.startsWith("lib/") && it.name.endsWith("/libsqlcipher.so") }
            .mapNotNull { entry ->
                val text = String(zip.getInputStream(entry).readBytes(), Charsets.ISO_8859_1)
                if (text.contains("nativeOpen")) null else entry.name
            }
            .toList()
        if (offenders.isNotEmpty()) {
            throw GradleException(
                "APK $apk ships a libsqlcipher.so without the Zetetic JNI " +
                    "(missing 'nativeOpen'): ${offenders.joinToString()}. The sqlite3 " +
                    "native-assets hook (pubspec hooks.user_defines.sqlite3.source: sqlcipher, " +
                    "intended for the Windows build) is shadowing the net.zetetic AAR's " +
                    "JNI-bearing lib on Android, which crashes at DB open (UnsatisfiedLinkError).",
            )
        }
    } finally {
        zip.close()
    }
}

mapOf("assembleDebug" to "packageDebug", "assembleRelease" to "packageRelease").forEach { (assemble, pkg) ->
    val verify = tasks.register("verifySqlcipherJni${pkg.removePrefix("package")}") {
        dependsOn(pkg)
        outputs.upToDateWhen { false }
        doLast {
            val apks = tasks.named(pkg).get().outputs.files
                .filter { it.isFile && it.name.endsWith(".apk") }
                .toList()
            if (apks.isEmpty()) {
                logger.info("verifySqlcipherJni: no APK output for $pkg, skipping")
            } else {
                apks.forEach { verifySqlcipherJniInApk(it) }
            }
        }
    }
    tasks.matching { it.name == assemble }.configureEach {
        finalizedBy(verify)
    }
}

flutter {
    source = "../.."
}
