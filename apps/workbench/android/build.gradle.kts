// Repositório Maven com o .aar do fabricante (plano, seção 5.4). A URL vem de gradle.properties,
// relativa a esta pasta android/, para alternar entre repositório local e interno sem editar código.
val sdk850MavenUrl = providers.gradleProperty("sdk850MavenUrl")

allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri(rootProject.file(sdk850MavenUrl.get()))
            content { includeGroup("com.sunway") }
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
