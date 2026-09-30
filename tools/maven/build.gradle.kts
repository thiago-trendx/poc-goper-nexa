// Publica o .aar do fabricante como com.sunway:sdk850:1.0.0 (plano, seção 5).
// Padrão: repositório local em ../../maven-repo (opção A).
// Opção B (Nexus/Artifactory): -Psdk850PublishUrl=https://... e credenciais em ~/.gradle/gradle.properties
// (sdk850PublishUser / sdk850PublishPassword). Nunca coloque credenciais no repositório.
plugins {
    `maven-publish`
}

group = "com.sunway"
version = "1.0.0"

val aarFile = file("../../third_party/sdk850/sdk850-v1.0-release.aar")
val publishUrl = providers.gradleProperty("sdk850PublishUrl").orElse("../../maven-repo")

publishing {
    publications {
        create<MavenPublication>("sdk850") {
            groupId = "com.sunway"
            artifactId = "sdk850"
            version = "1.0.0"
            artifact(aarFile) { extension = "aar" }
            pom {
                packaging = "aar"
                name.set("sdk850")
                description.set("SDK 850 do fabricante (Sunway) para comunicação serial com a máquina de força")
                // O .aar não inclui a biblioteca serial nativa; o POM declara como dependência transitiva.
                withXml {
                    val dependency = asNode().appendNode("dependencies").appendNode("dependency")
                    dependency.appendNode("groupId", "com.licheedev")
                    dependency.appendNode("artifactId", "android-serialport")
                    dependency.appendNode("version", "2.1.4")
                    dependency.appendNode("scope", "compile")
                }
            }
        }
    }
    repositories {
        maven {
            name = "sdk850"
            val url = publishUrl.get()
            if (url.startsWith("http")) {
                setUrl(uri(url))
                credentials {
                    username = providers.gradleProperty("sdk850PublishUser").orNull
                    password = providers.gradleProperty("sdk850PublishPassword").orNull
                }
            } else {
                setUrl(uri(file(url)))
            }
        }
    }
}

// Metadados Gradle não existem para um .aar solto; só o POM é publicado.
tasks.withType<GenerateModuleMetadata>().configureEach { enabled = false }

tasks.register("checkAar") {
    doFirst { require(aarFile.exists()) { "AAR não encontrado: $aarFile" } }
}
tasks.named("publish") { dependsOn("checkAar") }
