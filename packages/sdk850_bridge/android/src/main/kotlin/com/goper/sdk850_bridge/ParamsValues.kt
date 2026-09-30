package com.goper.sdk850_bridge

/** Faixa válida de um campo de `DeviceParams`, do Javadoc do SDK. */
class ParamRange(val key: String, val min: Int, val max: Int)

/** Faixas dos 11 campos de `DeviceParams` (plano, seção 3.1). Os nomes são os do SDK. */
object ParamRanges {
    val all: List<ParamRange> = listOf(
        ParamRange("minForce", 5, 20),
        ParamRange("maxForce", 50, 150),
        ParamRange("inactiveForce", 2, 20),
        ParamRange("maxLength", 10, 255),
        ParamRange("ratedSpeed", 1, 2000),
        ParamRange("ropeGuideDiameter", 1, 255),
        ParamRange("orginMinDistance", 1, 50),
        ParamRange("orginMaxDistance", 2, 100),
        ParamRange("velocityRange", 0, 50),
        ParamRange("torqueVariationCycle", 0, 100),
        ParamRange("torqueCoefficient", 1, 20)
    )

    val keys: Set<String> = all.map { it.key }.toSet()
}

/** Os 11 campos de calibração do `DeviceParams`, sem depender da classe do SDK. */
data class ParamsValues(
    val minForce: Int,
    val maxForce: Int,
    val inactiveForce: Int,
    val maxLength: Int,
    val ratedSpeed: Int,
    val ropeGuideDiameter: Int,
    val orginMinDistance: Int,
    val orginMaxDistance: Int,
    val velocityRange: Int,
    val torqueVariationCycle: Int,
    val torqueCoefficient: Int
) {
    fun toMap(): Map<String, Any?> = linkedMapOf(
        "minForce" to minForce,
        "maxForce" to maxForce,
        "inactiveForce" to inactiveForce,
        "maxLength" to maxLength,
        "ratedSpeed" to ratedSpeed,
        "ropeGuideDiameter" to ropeGuideDiameter,
        "orginMinDistance" to orginMinDistance,
        "orginMaxDistance" to orginMaxDistance,
        "velocityRange" to velocityRange,
        "torqueVariationCycle" to torqueVariationCycle,
        "torqueCoefficient" to torqueCoefficient
    )

    companion object {
        /** Monta a partir de um mapa já validado (todas as chaves de [ParamRanges] presentes). */
        fun fromMap(map: Map<String, Int>) = ParamsValues(
            minForce = map.getValue("minForce"),
            maxForce = map.getValue("maxForce"),
            inactiveForce = map.getValue("inactiveForce"),
            maxLength = map.getValue("maxLength"),
            ratedSpeed = map.getValue("ratedSpeed"),
            ropeGuideDiameter = map.getValue("ropeGuideDiameter"),
            orginMinDistance = map.getValue("orginMinDistance"),
            orginMaxDistance = map.getValue("orginMaxDistance"),
            velocityRange = map.getValue("velocityRange"),
            torqueVariationCycle = map.getValue("torqueVariationCycle"),
            torqueCoefficient = map.getValue("torqueCoefficient")
        )
    }
}
