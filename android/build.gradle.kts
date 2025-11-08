import com.android.build.gradle.BaseExtension
import groovy.util.XmlSlurper

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

// --- BEGIN namespace shim for AGP 8.x ---
subprojects { subproject ->
    afterEvaluate {
        if (subproject.plugins.hasPlugin("com.android.library") ||
            subproject.plugins.hasPlugin("com.android.application")
        ) {
            val androidExt = subproject.extensions.findByName("android")
            if (androidExt is BaseExtension) {
                val hasNs = try {
                    !androidExt.namespace.isNullOrBlank()
                } catch (_: Exception) {
                    false
                }
                if (!hasNs) {
                    val manifestFile = androidExt.sourceSets.getByName("main").manifest.srcFile
                    if (manifestFile != null && manifestFile.exists()) {
                        val pkg = XmlSlurper().parse(manifestFile).getProperty("@package")?.toString()
                        if (!pkg.isNullOrBlank()) {
                            androidExt.namespace = pkg
                            println("[namespace-shim] ${subproject.name} -> ${pkg}")
                        }
                    }
                }
            }
        }
    }
}
// --- END namespace shim ---

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
