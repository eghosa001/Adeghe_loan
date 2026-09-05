import java.util.zip.ZipEntry
import java.util.zip.ZipFile

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.adeghe.professionalservices.loantrack"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.adeghe.professionalservices.loantrack"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
            val storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            val keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            val keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            if (!keystorePath.isNullOrBlank() && !storePassword.isNullOrBlank() &&
                !keyAlias.isNullOrBlank() && !keyPassword.isNullOrBlank()) {
                storeFile = file(keystorePath)
                this.storePassword = storePassword
                this.keyAlias = keyAlias
                this.keyPassword = keyPassword
            }
        }
    }

    buildTypes {
        release {
            val hasReleaseSigning = listOf(
                System.getenv("ANDROID_KEYSTORE_PATH"),
                System.getenv("ANDROID_KEYSTORE_PASSWORD"),
                System.getenv("ANDROID_KEY_ALIAS"),
                System.getenv("ANDROID_KEY_PASSWORD"),
            ).all { !it.isNullOrBlank() }
            check(hasReleaseSigning) {
                "Production release builds require ANDROID_KEYSTORE_PATH, " +
                    "ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS and ANDROID_KEY_PASSWORD. " +
                    "Refusing to sign a release APK with the debug keystore."
            }
            signingConfig = signingConfigs.getByName("release")
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

tasks.matching { it.name.startsWith("copyJniLibsflutterBuild") }.configureEach {
    doLast {
        val staged = outputs.files.singleFile
        staged.walkTopDown()
            .filter { it.isFile && it.name == "libsqlcipher.so" }
            .forEach { it.delete() }
    }
}

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
                "native-assets hook is shadowing the net.zetetic AAR's JNI-bearing " +
                "library, which would crash at database open."
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
            apks.forEach { verifySqlcipherJniInApk(it) }
        }
    }
    tasks.matching { it.name == assemble }.configureEach {
        finalizedBy(verify)
    }
}

flutter {
    source = "../.."
}
