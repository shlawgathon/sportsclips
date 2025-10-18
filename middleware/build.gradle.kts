val kotlin_version: String by project
val logback_version: String by project
val mongo_version: String by project

plugins {
    kotlin("jvm") version "2.2.20"
    id("io.ktor.plugin") version "3.3.0"
    id("org.jetbrains.kotlin.plugin.serialization") version "2.2.20"
}

group = "gg.growly"
version = "0.0.1"

application {
    mainClass = "io.ktor.server.netty.EngineMain"
}

dependencies {
    implementation("org.openfolder:kotlin-asyncapi-ktor:3.1.2")
    implementation("io.ktor:ktor-server-core")
    implementation("com.ucasoft.ktor:ktor-simple-cache:0.55.3")
    implementation("com.ucasoft.ktor:ktor-simple-memory-cache:0.55.3")
    implementation("io.ktor:ktor-server-auth")
    implementation("io.ktor:ktor-server-content-negotiation")
    implementation("io.ktor:ktor-serialization-kotlinx-json")
    implementation("io.ktor:ktor-server-sessions")
    implementation("dev.hayden:khealth:3.0.2")
    implementation("org.mongodb:mongodb-driver-core:$mongo_version")
    implementation("org.mongodb:mongodb-driver-sync:$mongo_version")
    implementation("org.mongodb:bson:$mongo_version")
    implementation("io.ktor:ktor-server-netty")
    implementation("ch.qos.logback:logback-classic:$logback_version")
    implementation("io.ktor:ktor-server-config-yaml")
    testImplementation("io.ktor:ktor-server-test-host")
    testImplementation("org.jetbrains.kotlin:kotlin-test-junit:$kotlin_version")
}
