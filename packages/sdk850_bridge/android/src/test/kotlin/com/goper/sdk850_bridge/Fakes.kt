package com.goper.sdk850_bridge

import com.sunway.sdk850.port.bean.DeviceInfo
import com.sunway.sdk850.port.bean.DeviceStatus

/** [Scheduler] com relógio virtual: nada roda até o teste chamar [advance]. */
class FakeScheduler : Scheduler {
    private class Entry(val at: Long, val seq: Int, val task: Runnable)

    private val entries = mutableListOf<Entry>()
    private var seq = 0

    var now = 0L
        private set

    val pendingTasks: Int
        get() = entries.size

    override fun postDelayed(task: Runnable, delayMs: Long) {
        entries.add(Entry(now + delayMs, seq++, task))
    }

    override fun removeCallbacks(task: Runnable) {
        entries.removeAll { it.task === task }
    }

    fun advance(ms: Long) {
        val target = now + ms
        while (true) {
            val next = entries
                .filter { it.at <= target }
                .minWithOrNull(compareBy({ it.at }, { it.seq })) ?: break
            entries.remove(next)
            now = next.at
            next.task.run()
        }
        now = target
    }
}

class FakeClock(var monotonic: Long = 1_000, var epoch: Long = 1_750_000_000_000) : Clock {
    override fun monotonicMs(): Long = monotonic
    override fun epochMs(): Long = epoch
}

/** [SdkPort] que registra as chamadas em [calls], sem SDK nem serial. */
class FakePort : SdkPort {
    val calls = mutableListOf<String>()
    val sent = mutableListOf<ByteArray>()

    var connected = false
    var pending = 0
    var connectResult = true
    var state = "IDLE"
    var portPath: String? = null
    var failSend: Exception? = null

    val controlBytes = byteArrayOf(0x0C)
    val infoBytes = byteArrayOf(0x0D)

    var deviceInitCount = 0
    var configured: List<Any>? = null
    var listener: PortListener? = null

    override fun initDevice(spFileName: String) {
        deviceInitCount++
        calls += "initDevice:$spFileName"
    }

    override fun configure(baudRate: Int, sendIntervalMs: Long, testTimeMs: Long, logEnabled: Boolean) {
        configured = listOf(baudRate, sendIntervalMs, testTimeMs, logEnabled)
        calls += "configure"
    }

    override fun register(listener: PortListener) {
        this.listener = listener
        calls += "register"
    }

    override fun unregister() {
        listener = null
        calls += "unregister"
    }

    override fun autoConnect() {
        calls += "autoConnect"
    }

    override fun connect(portPath: String): Boolean {
        calls += "connect:$portPath"
        return connectResult
    }

    override fun reConnect() {
        calls += "reConnect"
    }

    override fun disconnect() {
        calls += "disconnect"
        connected = false
    }

    override fun isConnected(): Boolean = connected
    override fun stateName(): String = state
    override fun currentPortPath(): String? = portPath

    override fun send(data: ByteArray) {
        failSend?.let { throw it }
        sent += data
        calls += "send:" + data.joinToString("") { "%02X".format(it) }
    }

    override fun clearSendQueue() {
        calls += "clearSendQueue"
    }

    override fun pendingCount(): Int = pending
    /** Retrato dos `ControlParams` no instante de cada `controlCommand()` (o que iria no pacote). */
    val controlSnapshots = mutableListOf<ControlValues>()

    override fun controlCommand(): ByteArray {
        controlSnapshots += control
        return controlBytes
    }

    var control = defaultControl()

    override fun markStop() {
        calls += "markStop"
        control = control.copy(run = "STOP")
    }

    override fun controlValues(): ControlValues = control

    override fun setRunning(running: Boolean) {
        calls += "setRunning:$running"
        control = control.copy(run = if (running) "RUNNING" else "STOP")
    }

    override fun setForce(kg: Int) {
        calls += "setForce:$kg"
        control = control.copy(force = kg)
    }

    override fun setMode(mode: String) {
        calls += "setMode:$mode"
        control = control.copy(mode = mode)
    }

    override fun setCoefficient(kind: String, value: Int) {
        calls += "setCoefficient:$kind:$value"
        control = when (kind) {
            "centripetal" -> control.copy(centripetal = value)
            "centrifugal" -> control.copy(centrifugal = value)
            "velocity" -> control.copy(velocity = value)
            else -> control.copy(elastic = value)
        }
    }

    override fun setElasticMax(value: Int) {
        calls += "setElasticMax:$value"
        control = control.copy(maxElectric = value)
    }

    override fun setSafeMode(value: Int) {
        calls += "setSafeMode:$value"
        control = control.copy(safeMode = value)
    }

    override fun setBalancingForce(kg: Int) {
        calls += "setBalancingForce:$kg"
        control = control.copy(balancingForce = kg)
    }

    override fun setNeedSetOrigin(value: Boolean) {
        calls += "setNeedSetOrigin:$value"
        control = control.copy(needSetOrigin = value)
    }

    override fun setNeedErrorRestore(value: Boolean) {
        calls += "setNeedErrorRestore:$value"
        control = control.copy(needErrorRestor = value)
    }

    override fun setClearMode(mode: String) {
        calls += "setClearMode:$mode"
        control = control.copy(clearMode = mode)
    }

    override fun setRunErrorRestore() {
        calls += "setRunErrorRestore"
        control = control.copy(run = "ERROR_RESTORE")
    }

    override fun setMotorSelfCheck(value: Boolean) {
        calls += "setMotorSelfCheck:$value"
        control = control.copy(motorSelfCheck = value)
    }

    override fun setMotorPositions(p1: Int, p2: Int) {
        calls += "setMotorPositions:$p1:$p2"
        control = control.copy(motorPosition1 = p1, motorPosition2 = p2)
    }

    val paramsBytes = byteArrayOf(0x0A)
    var params = defaultParams()
    val applied = mutableListOf<ParamsValues>()

    override fun deviceParams(): ParamsValues = params

    override fun paramsCommand(values: ParamsValues): ByteArray {
        applied += values
        params = values
        calls += "applyParams"
        return paramsBytes
    }

    override fun deviceInfoQuery(): ByteArray = infoBytes

    override fun commandName(data: ByteArray): String =
        if (data.contentEquals(controlBytes)) "CONTROL" else "OTHER"

    /** Número de comandos de controle enviados até agora. */
    val controlSends: Int
        get() = sent.count { it.contentEquals(controlBytes) }
}

fun sampleStatus(): DeviceStatus = DeviceStatus()

fun sampleInfo(): DeviceInfo = DeviceInfo("SW-1", 41, "P-9")

fun defaultParams() = ParamsValues(
    minForce = 5,
    maxForce = 100,
    inactiveForce = 5,
    maxLength = 200,
    ratedSpeed = 1000,
    ropeGuideDiameter = 10,
    orginMinDistance = 5,
    orginMaxDistance = 50,
    velocityRange = 20,
    torqueVariationCycle = 50,
    torqueCoefficient = 10
)

fun defaultControl() = ControlValues(
    run = "STOP",
    mode = "STANDARD",
    force = 0,
    centripetal = 0,
    centrifugal = 0,
    velocity = 0,
    elastic = 0,
    safeMode = 0,
    clearMode = "NONE",
    motorPosition1 = 0,
    motorPosition2 = 0,
    motorSelfCheck = false,
    balancingForce = 0,
    maxElectric = 50,
    needSetOrigin = false,
    needErrorRestor = false
)
