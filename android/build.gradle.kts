allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// VO-10: some plugin subprojects (receive_sharing_intent, file_picker, ...)
// leave their Java/Kotlin JVM targets at mismatched defaults, causing a
// "Inconsistent JVM Target Compatibility" build failure. Force a matching
// Java+Kotlin toolchain for those plugin modules only — :app already sets
// its own explicit Java 17 / kotlinOptions and evaluates first (see
// evaluationDependsOn above), so it's excluded to avoid a toolchain conflict.
subprojects {
    if (project.name == "app") return@subprojects
    plugins.withId("org.jetbrains.kotlin.android") {
        extensions.findByType(org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java)
            ?.jvmToolchain(17)
    }
    plugins.withId("kotlin-android") {
        extensions.findByType(org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java)
            ?.jvmToolchain(17)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
