allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir = File("C:/Users/Public/DocSiftBuild")
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val newSubprojectBuildDir = File(newBuildDir, project.name)
    project.layout.buildDirectory.set(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
    // Suppress the legacy 4 KB-aligned libonnxruntime.so bundled in the onnxruntime Flutter
    // plugin so :app supplies the official 16 KB-aligned com.microsoft.onnxruntime AAR cleanly.
    if (project.name == "onnxruntime") {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.apply {
                sourceSets.getByName("main").jniLibs.setSrcDirs(emptyList<File>())
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
