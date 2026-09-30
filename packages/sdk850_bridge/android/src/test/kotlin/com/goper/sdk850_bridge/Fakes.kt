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
    override fun controlCommand(): ByteArray = controlBytes

    override fun markStop() {
        calls += "markStop"
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
