package com.goper.sdk850_bridge

import com.sunway.sdk850.port.bean.DeviceInfo
import com.sunway.sdk850.port.bean.DeviceStatus

/**
 * Converte objetos do SDK nos `Map` do contrato (seção 6.2 do plano). Enums vão como `name()`.
 * Os getters são usados de propósito: são os que o Javadoc documenta.
 */
object Mappers {
    fun status(status: DeviceStatus, tsMonotonicMs: Long, tsEpochMs: Long): Map<String, Any?> = mapOf(
        "type" to "status",
        "run" to status.getRun()?.name,
        "mode" to status.getMode()?.name,
        "force" to status.getForce(),
        "realForce" to status.getRealForce(),
        "speed" to status.getSpeed(),
        "distance" to status.getDistance(),
        "pullNum" to status.getPullNum(),
        "errorCode" to status.getErrorCode(),
        "temperature" to status.getTemperature(),
        "liftMotorStatus" to status.getLiftMotorStatus(),
        "liftMotorError1" to status.getLiftMotorError1(),
        "liftMotorError2" to status.getLiftMotorError2(),
        "verityCodeError" to status.getVerityCodeError(),
        "tsMonotonicMs" to tsMonotonicMs,
        "tsEpochMs" to tsEpochMs
    )

    fun deviceInfo(info: DeviceInfo): Map<String, Any?> = mapOf(
        "type" to "deviceInfo",
        "softwareNum" to info.getSoftwareNum(),
        "versionCode" to info.getVersionCode(),
        "produceCode" to info.getProduceCode()
    )

    /** [state]: `connected`, `failed`, `disconnected` ou `error`. */
    fun connection(state: String, portPath: String?, reason: String? = null): Map<String, Any?> =
        buildMap {
            put("type", "connection")
            put("state", state)
            put("portPath", portPath)
            if (reason != null) put("reason", reason)
        }

    /** [direction]: `tx` ou `rx`. */
    fun log(direction: String, packetType: String, hex: String?, tsEpochMs: Long): Map<String, Any?> =
        buildMap {
            put("type", "log")
            put("direction", direction)
            put("packetType", packetType)
            if (hex != null) put("hex", hex)
            put("tsEpochMs", tsEpochMs)
        }

    /** Campos de `DeviceParams` no mesmo nível do `type`, como no contrato. */
    fun paramsAck(values: ParamsValues): Map<String, Any?> = linkedMapOf<String, Any?>("type" to "paramsAck") + values.toMap()

    fun controlParams(values: ControlValues): Map<String, Any?> = values.toMap()

    /** Evento `liftMotor`; [phase] é `started`, `completed` ou `timeout`. */
    fun liftMotor(phase: String, remainingSec: Int): Map<String, Any?> =
        mapOf("type" to "liftMotor", "phase" to phase, "remainingSec" to remainingSec)

    fun connectionInfo(state: String, portPath: String?): Map<String, Any?> =
        mapOf("state" to state, "portPath" to portPath)

    /** Bytes em hexadecimal maiúsculo separados por espaço, por exemplo `AA 55 0F`. */
    fun hex(bytes: ByteArray): String = bytes.joinToString(" ") { "%02X".format(it.toInt() and 0xFF) }
}
