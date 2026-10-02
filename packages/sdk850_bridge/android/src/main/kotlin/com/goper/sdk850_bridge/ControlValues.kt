package com.goper.sdk850_bridge

/**
 * Faixas dos comandos de controle. Origem: Javadoc (`balancingForce`, `safeMode`, `velocity`) e a
 * interface do demo do fabricante (`AdjustView`: concêntrico e excêntrico de 0 a 6, isocinético
 * e elástico de 0 a 10, força de `minForce` a `maxForce`).
 */
object ControlLimits {
    val MODES: Set<String> = setOf("STANDARD", "CENTRIPETAL", "CENTRIFUGAL", "VELOCITY", "ELASTIC")
    val COEFFICIENT_KINDS: Set<String> = setOf("centripetal", "centrifugal", "velocity", "elastic")

    /** 0 = normal, 51 = falha/fadiga, 53 = proteção. */
    val SAFE_MODES: Set<Int> = setOf(0, 51, 53)

    const val CENTRIPETAL_MAX = 6
    const val CENTRIFUGAL_MAX = 6
    const val ELASTIC_MAX = 10
    const val BALANCING_FORCE_MAX = 25
}

/** Retrato dos `ControlParams` do SDK, sem depender da classe do SDK. Enums vão como `name()`. */
data class ControlValues(
    val run: String?,
    val mode: String?,
    val force: Int,
    val centripetal: Int,
    val centrifugal: Int,
    val velocity: Int,
    val elastic: Int,
    val safeMode: Int,
    val clearMode: String?,
    val motorPosition1: Int,
    val motorPosition2: Int,
    val motorSelfCheck: Boolean,
    val balancingForce: Int,
    val maxElectric: Int,
    val needSetOrigin: Boolean,
    val needErrorRestor: Boolean
) {
    fun toMap(): Map<String, Any?> = linkedMapOf(
        "run" to run,
        "mode" to mode,
        "force" to force,
        "centripetal" to centripetal,
        "centrifugal" to centrifugal,
        "velocity" to velocity,
        "elastic" to elastic,
        "safeMode" to safeMode,
        "clearMode" to clearMode,
        "motorPosition1" to motorPosition1,
        "motorPosition2" to motorPosition2,
        "motorSelfCheck" to motorSelfCheck,
        "balancingForce" to balancingForce,
        "maxElectric" to maxElectric,
        "needSetOrigin" to needSetOrigin,
        "needErrorRestor" to needErrorRestor
    )
}
